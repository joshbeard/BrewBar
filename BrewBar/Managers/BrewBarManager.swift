import Foundation

// MARK: - BrewBar Operation Manager
class BrewBarManager {
    static let shared = BrewBarManager()

    var updateCheckTask: Process?
    var updateProcess: Process?
    var isUpdateRunning = false

    // Default brew commands
    var defaultUpdateCommand = ["update"]
    var defaultUpgradeCommand = ["upgrade"]

    // UserDefaults keys
    let updateCommandsKey = "updateCommands"
    let upgradeCommandsKey = "upgradeCommands"

    // Current brew commands (read from UserDefaults or use defaults)
    var updateCommand: [String] {
        get {
            return UserDefaults.standard.stringArray(forKey: updateCommandsKey) ?? defaultUpdateCommand
        }
        set {
            UserDefaults.standard.set(newValue, forKey: updateCommandsKey)
        }
    }

    var upgradeCommand: [String] {
        get {
            return UserDefaults.standard.stringArray(forKey: upgradeCommandsKey) ?? defaultUpgradeCommand
        }
        set {
            UserDefaults.standard.set(newValue, forKey: upgradeCommandsKey)
        }
    }

    // Helper method to parse package information with versions
    func parsePackagesWithVersions(from output: String) -> [PackageInfo] {
        var packages: [PackageInfo] = []
        let lines = output.components(separatedBy: "\n")

        LoggingUtility.shared.log("Parsing output from brew outdated")

        for line in lines {
            // Skip empty lines or lines with our custom output
            if line.isEmpty || line.contains("Checking for") || line.contains("Running:") {
                continue
            }

            // Check for tap/cask information
            var source = ""

            // Look for tap information with improved detection
            if line.contains("homebrew/cask") {
                source = "cask"
            } else if line.contains("homebrew/core") {
                source = "core"
            } else {
                // Look for other tap markers with enhanced pattern matching
                // First check for pattern like "[tap/name]"
                if let tapRange = line.range(of: "\\[.+?\\]", options: .regularExpression) {
                    source = String(line[tapRange]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                }
                // Check for pattern like "from tap/name"
                else if let fromRange = line.range(of: "from [^\\s]+", options: .regularExpression) {
                    let fromText = String(line[fromRange])
                    source = fromText.replacingOccurrences(of: "from ", with: "")
                }
                // Additional pattern to catch "tap_name/formula_name"
                else if let range = line.range(of: "/[^\\s)]+", options: .regularExpression) {
                    let fullPath = String(line[range.lowerBound..<range.upperBound])
                    let components = fullPath.components(separatedBy: "/")
                    if components.count >= 2 {
                        // Keep the full tap path instead of just the first component
                        // We need to remove the leading slash and retain the rest
                        source = fullPath.hasPrefix("/") ? String(fullPath.dropFirst()) : fullPath
                    }
                }
            }

            // Try to parse version information with various patterns
            var packageName = ""
            var currentVersion = ""
            var availableVersion = ""
            var matched = false

            // Pattern 1: Standard format like "ffmpeg (6.0_1) < 6.1"
            if let regex = try? NSRegularExpression(pattern: "([^ ]+) \\(([^)]+)\\) < (.+?)($| |\\[)") {
                let nsString = line as NSString
                let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsString.length))

                if let match = matches.first, match.numberOfRanges >= 4 {
                    packageName = nsString.substring(with: match.range(at: 1))
                    currentVersion = nsString.substring(with: match.range(at: 2))
                    availableVersion = nsString.substring(with: match.range(at: 3))
                    matched = true
                }
            }

            // Pattern 2: Format with arrow like "ffmpeg 6.0_1 -> 6.1"
            if !matched, let regex = try? NSRegularExpression(pattern: "([^ ]+)\\s+([^ ]+)\\s+->\\s+([^ ]+)") {
                let nsString = line as NSString
                let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsString.length))

                if let match = matches.first, match.numberOfRanges >= 4 {
                    packageName = nsString.substring(with: match.range(at: 1))
                    currentVersion = nsString.substring(with: match.range(at: 2))
                    availableVersion = nsString.substring(with: match.range(at: 3))
                    matched = true
                }
            }

            // Pattern 3: Handle special version cases like "beta" versions
            if !matched, let regex = try? NSRegularExpression(pattern: "([^ ]+)\\s+\\((.+?)\\)(\\s+.+?|$)") {
                let nsString = line as NSString
                let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsString.length))

                if let match = matches.first, match.numberOfRanges >= 3 {
                    packageName = nsString.substring(with: match.range(at: 1))
                    currentVersion = nsString.substring(with: match.range(at: 2))

                    // Try to find available version after the current version
                    if let availRange = line.range(of: "\\s+[a-zA-Z0-9._-]+$", options: .regularExpression) {
                        availableVersion = String(line[availRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        // If no clear available version, mark as "new version"
                        availableVersion = "new version"
                    }

                    matched = true
                }
            }

            // If no patterns matched, try to extract the package name at minimum
            if !matched {
                // Remove potential known prefixes like "homebrew/cask/"
                let cleanLine = line.replacingOccurrences(of: "homebrew/cask/", with: "")
                                    .replacingOccurrences(of: "homebrew/core/", with: "")

                // Get the first word as package name
                if let firstWord = cleanLine.components(separatedBy: " ").first, !firstWord.isEmpty {
                    packageName = firstWord

                    // Try to extract a version-like string
                    if let versionRange = cleanLine.range(of: "\\d+[\\d._-]+\\w*", options: .regularExpression) {
                        let versionString = String(cleanLine[versionRange])

                        if cleanLine.contains("->") {
                            // If there's an arrow, figure out which side is current vs. available
                            let parts = cleanLine.components(separatedBy: "->").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            if parts.count >= 2 {
                                currentVersion = parts[0].components(separatedBy: " ").last ?? "?"
                                availableVersion = parts[1].components(separatedBy: " ").first ?? "?"
                            } else {
                                currentVersion = "?"
                                availableVersion = versionString
                            }
                        } else {
                            currentVersion = "?"
                            availableVersion = versionString
                        }
                    } else {
                        currentVersion = "?"
                        availableVersion = "?"
                    }
                }
            }

            // Clean up the package name to handle tap prefixes in the name
            if packageName.contains("/") {
                let components = packageName.components(separatedBy: "/")
                if components.count >= 2 {
                    // If source is empty, use the tap part as source
                    if source.isEmpty {
                        source = components[0]
                    }
                    // Use the last component as the package name
                    packageName = components.last ?? packageName
                }
            }

            // Only add if we got a package name
            if !packageName.isEmpty {
                let packageInfo = PackageInfo(
                    name: packageName,
                    currentVersion: currentVersion,
                    availableVersion: availableVersion,
                    source: source
                )
                packages.append(packageInfo)
            }
        }

        // Check for missing tap information and try to enrich it
        enrichPackagesWithTapInfo(packages: packages) { enrichedPackages in
            packages = enrichedPackages
        }

        LoggingUtility.shared.log("Total packages parsed: \(packages.count)")
        return packages
    }

    // Helper method to enrich packages with tap information asynchronously
    func enrichPackagesWithTapInfo(packages: [PackageInfo], completion: @escaping ([PackageInfo]) -> Void) {
        // Skip if no packages to process
        if packages.isEmpty {
            completion(packages)
            return
        }

        // Only process packages without source info
        let packagesToProcess = packages.filter { $0.source.isEmpty }
        if packagesToProcess.isEmpty {
            completion(packages)
            return
        }

        LoggingUtility.shared.log("Starting async tap enrichment for \(packagesToProcess.count) packages")

        // Create a copy of packages to work with in background thread
        let packagesCopy = packages

        // Create a dispatch group to track all package info requests
        let dispatchGroup = DispatchGroup()
        var updatedPackages = [PackageInfo]()
        let packagesLock = NSLock() // Thread safety for concurrent access

        // Process in background
        for package in packagesCopy where package.source.isEmpty {
            var updatedPackage = package

            dispatchGroup.enter()
            // Use brew info to get package details with JSON format
            BrewBarUtility.shared.runBrewCommand(["info", "--json=v1", package.name]) { infoStr, status, error in
                defer { dispatchGroup.leave() }

                if let error = error {
                    LoggingUtility.shared.log("Error running brew info for \(package.name): \(error.localizedDescription)")
                } else if let infoOutput = infoStr, status == 0 {
                    // Check if there's a "tap" field in the JSON output
                    if infoOutput.contains("\"tap\":") {
                        // Simple extraction using string search
                        if let range = infoOutput.range(of: "\"tap\":\\s*\"([^\"]+)\"", options: .regularExpression) {
                            let match = infoOutput[range]
                            if let tapRange = match.range(of: "\"[^\"]+\"", options: .regularExpression, range: match.index(match.startIndex, offsetBy: 6)..<match.endIndex) {
                                let tap = infoOutput[tapRange].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                                updatedPackage = PackageInfo(
                                    name: package.name,
                                    currentVersion: package.currentVersion,
                                    availableVersion: package.availableVersion,
                                    source: tap
                                )
                            }
                        }
                    }
                }

                // Safely add to the results array
                packagesLock.lock()
                updatedPackages.append(updatedPackage)
                packagesLock.unlock()
            }
        }

        dispatchGroup.notify(queue: .main) {
            // Update the original packages with the enriched info
            var enrichedPackages = packages
            for (index, package) in enrichedPackages.enumerated() {
                if package.source.isEmpty {
                    if let updatedPackage = updatedPackages.first(where: { $0.name == package.name && !$0.source.isEmpty }) {
                        enrichedPackages[index] = updatedPackage
                    }
                }
            }
            completion(enrichedPackages)
        }
    }

    // Fetch installed Homebrew packages
    func fetchInstalledPackages(completion: @escaping ([InstalledPackageInfo]) -> Void) {
        LoggingUtility.shared.log("Fetching installed packages")

        guard BrewBarUtility.shared.brewPath != nil else {
            LoggingUtility.shared.log("ERROR: Brew executable not found for fetching installed packages")
            completion([])
            return
        }

        let brewUtil = BrewBarUtility.shared
        var installedPackages: [InstalledPackageInfo] = []

        // Fetch formulae and casks in parallel using dispatch groups
        let dispatchGroup = DispatchGroup()

        // Fetch installed formulae
        dispatchGroup.enter()
        brewUtil.runBrewCommand(["list", "--versions", "--formula"]) { formulaeOutput, status, error in
            defer { dispatchGroup.leave() }

            if let error = error {
                LoggingUtility.shared.log("Error fetching formulae: \(error.localizedDescription)")
                return
            }

            if let output = formulaeOutput {
                let formulaeLines = output.components(separatedBy: "\n")
                for line in formulaeLines {
                    if !line.isEmpty {
                        let components = line.components(separatedBy: " ")
                        if components.count >= 2 {
                            let name = components[0]
                            let version = components[1]
                            let packageInfo = InstalledPackageInfo(
                                name: name,
                                version: version,
                                source: "formula"
                            )
                            installedPackages.append(packageInfo)
                        }
                    }
                }
            }
        }

        // Fetch installed casks
        dispatchGroup.enter()
        brewUtil.runBrewCommand(["list", "--versions", "--cask"]) { casksOutput, status, error in
            defer { dispatchGroup.leave() }

            if let error = error {
                LoggingUtility.shared.log("Error fetching casks: \(error.localizedDescription)")
                return
            }

            if let output = casksOutput {
                let casksLines = output.components(separatedBy: "\n")
                for line in casksLines {
                    if !line.isEmpty {
                        let components = line.components(separatedBy: " ")
                        if components.count >= 2 {
                            let name = components[0]
                            let version = components[1]
                            let packageInfo = InstalledPackageInfo(
                                name: name,
                                version: version,
                                source: "cask"
                            )
                            installedPackages.append(packageInfo)
                        }
                    }
                }
            }
        }

        // When both operations complete, sort and return the packages
        dispatchGroup.notify(queue: .main) {
            installedPackages.sort { $0.name < $1.name }
            LoggingUtility.shared.log("Found \(installedPackages.count) installed packages")
            completion(installedPackages)
        }
    }
}