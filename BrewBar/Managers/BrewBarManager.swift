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

    // Helper method to parse package information with versions from `brew outdated` output
    func parsePackagesWithVersions(from output: String) -> [PackageInfo] {
        var packages: [PackageInfo] = []
        let lines = output.components(separatedBy: "\n")

        LoggingUtility.shared.log("Parsing output from brew outdated")

        for line in lines {
            // Skip empty lines or lines with our custom output
            if line.isEmpty || line.contains("Checking for") || line.contains("Running:") || line.contains("==> Outdated") {
                continue
            }

            // Basic parsing: Assume format "package_name (current_version) != available_version [other_info]"
            // Or                 "package_name (current_version) < available_version [other_info]"
            // Or                 "package_name current_version -> available_version"

            var packageName = ""
            var currentVersion = ""
            var availableVersion = ""
            var matched = false

            // Pattern 1: (version) != new_version or < new_version
            if let regex = try? NSRegularExpression(pattern: "^([^ ]+) \\(([^)]+)\\) (!=|\\<) ([^ \\[]+)") {
                let nsString = line as NSString
                let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsString.length))
                if let match = matches.first, match.numberOfRanges >= 5 {
                    packageName = nsString.substring(with: match.range(at: 1))
                    currentVersion = nsString.substring(with: match.range(at: 2))
                    availableVersion = nsString.substring(with: match.range(at: 4))
                    matched = true
                }
            }

            // Pattern 2: current_version -> new_version (often used for casks or complex updates)
            if !matched, let regex = try? NSRegularExpression(pattern: "^([^ ]+)\\s+([^ ]+)\\s+->\\s+([^ ]+)") {
                let nsString = line as NSString
                let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsString.length))
                if let match = matches.first, match.numberOfRanges >= 4 {
                    packageName = nsString.substring(with: match.range(at: 1))
                    currentVersion = nsString.substring(with: match.range(at: 2))
                    availableVersion = nsString.substring(with: match.range(at: 3))
                    matched = true
                }
            }

            // Pattern 3: Catch simple names where versions might be missing or weird (fallback)
            if !matched, let firstWord = line.components(separatedBy: " ").first, !firstWord.isEmpty {
                 packageName = firstWord
                 // Leave versions empty, enrichment step will handle if possible
                 currentVersion = "?"
                 availableVersion = "?"
                 matched = true // Mark as matched to add to list
            }


            // Only add if we got a package name
            if matched && !packageName.isEmpty {
                let packageInfo = PackageInfo(
                    name: packageName,
                    currentVersion: currentVersion,
                    availableVersion: availableVersion,
                    source: "" // Source will be determined later
                )
                packages.append(packageInfo)
            } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                LoggingUtility.shared.log("Skipping unparsed line: \(line)")
            }
        }

        LoggingUtility.shared.log("Finished parsing \(packages.count) outdated packages (pre-enrichment)")
        return packages
    }

    // Helper method to enrich packages with tap information asynchronously
    // THIS FUNCTION IS DEPRECATED and will be removed. Use enrichOutdatedPackagesWithSource instead.
    func enrichPackagesWithTapInfo(packages: [PackageInfo], completion: @escaping ([PackageInfo]) -> Void) {
        // ... function body remains but should not be called ...
        LoggingUtility.shared.log("WARNING: Deprecated enrichPackagesWithTapInfo called.")
        completion(packages) // Immediately return original packages
    }

    // Structs for parsing `brew info --json=v2 --installed`
    struct BrewInfoV2: Decodable {
        let formulae: [FormulaInfo]
        let casks: [CaskInfo]
    }
    struct FormulaInfo: Decodable {
        let name: String
        let full_name: String
        let tap: String? // e.g., "homebrew/core"
        // Add other fields if needed
    }
    struct CaskInfo: Decodable {
        let token: String // This is the primary name/ID for casks
        let full_token: String
        let tap: String? // e.g., "homebrew/cask"
        // Add other fields if needed
    }

    // Enrich outdated packages with their source (formula/cask) using brew info
    func enrichOutdatedPackagesWithSource(packages: [PackageInfo], completion: @escaping ([PackageInfo]) -> Void) {
        if packages.isEmpty {
            LoggingUtility.shared.log("Enrichment: No packages to enrich.")
            completion([])
            return
        }

        LoggingUtility.shared.log("Enrichment: Starting source enrichment for \(packages.count) packages.")

        // Get installed formulas and casks first to use as reference
        let dispatchGroup = DispatchGroup()
        var installedFormulae = Set<String>()
        var installedCasks = Set<String>()

        // Get installed formulas
        dispatchGroup.enter()
        BrewBarUtility.shared.runBrewCommand(["list", "--formula"]) { output, status, error in
            defer { dispatchGroup.leave() }
            if let formulaOutput = output, status == 0 {
                formulaOutput.split(separator: "\n").forEach { name in
                    installedFormulae.insert(String(name))
                }
                LoggingUtility.shared.log("Found \(installedFormulae.count) installed formulas")
            }
        }

        // Get installed casks
        dispatchGroup.enter()
        BrewBarUtility.shared.runBrewCommand(["list", "--cask"]) { output, status, error in
            defer { dispatchGroup.leave() }
            if let caskOutput = output, status == 0 {
                caskOutput.split(separator: "\n").forEach { name in
                    installedCasks.insert(String(name))
                }
                LoggingUtility.shared.log("Found \(installedCasks.count) installed casks")
            }
        }

        // After we have both lists
        dispatchGroup.notify(queue: .global(qos: .userInitiated)) {
            // Now enrich each package
            var enrichedPackages = packages

            for i in 0..<enrichedPackages.count {
                let packageName = enrichedPackages[i].name

                // Simple, straightforward source determination
                if installedCasks.contains(packageName) {
                    enrichedPackages[i].source = "cask"
                } else if installedFormulae.contains(packageName) {
                    enrichedPackages[i].source = "formula"
                } else if packageName.contains("/") {
                    // For packages with a slash, use the first part as the tap
                    let components = packageName.components(separatedBy: "/")
                    if components.count >= 2 {
                        enrichedPackages[i].source = components[0]
                    } else {
                        enrichedPackages[i].source = "formula" // Default
                    }
                } else {
                    // Directly check with brew info as a last resort
                    var source = "formula" // Default to formula

                    // Try to determine if it's a cask by running a synchronous command
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: BrewBarUtility.shared.brewPath ?? "/opt/homebrew/bin/brew")
                    task.arguments = ["info", "--cask", packageName]

                    // Capture exit status only, output doesn't matter
                    task.standardOutput = FileHandle.nullDevice
                    task.standardError = FileHandle.nullDevice

                    do {
                        try task.run()
                        task.waitUntilExit()

                        // If exit code is 0, it's a cask
                        if task.terminationStatus == 0 {
                            source = "cask"
                        }
                    } catch {
                        // If there's an error, stay with default "formula"
                    }

                    enrichedPackages[i].source = source
                }

                LoggingUtility.shared.log("Set source for '\(packageName)' to '\(enrichedPackages[i].source)'")
            }

            // Return the enriched packages on the main thread
            DispatchQueue.main.async {
                completion(enrichedPackages)
            }
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