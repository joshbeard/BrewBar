import Foundation
import Observation

// MARK: - BrewBar Operation Manager

@Observable
class BrewBarManager {
    static let shared = BrewBarManager()

    var isCheckInProgress = false
    var isUpdateRunning = false

    let defaultUpdateCommand = ["update"]
    let defaultUpgradeCommand = ["upgrade"]

    private let updateCommandsKey = "updateCommands"
    private let upgradeCommandsKey = "upgradeCommands"

    var updateCommand: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: updateCommandsKey)
                ?? defaultUpdateCommand
        }
        set {
            UserDefaults.standard.set(newValue, forKey: updateCommandsKey)
        }
    }

    var upgradeCommand: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: upgradeCommandsKey)
                ?? defaultUpgradeCommand
        }
        set {
            UserDefaults.standard.set(newValue, forKey: upgradeCommandsKey)
        }
    }

    // MARK: - Parsing

    struct BrewInfoV2: Decodable {
        let formulae: [FormulaInfo]
        let casks: [CaskInfo]
    }

    struct FormulaInfo: Decodable {
        let name: String
        let full_name: String
        let tap: String?
    }

    struct CaskInfo: Decodable {
        let token: String
        let full_token: String
        let tap: String?
        let installed: String?
    }

    func parsePackagesWithVersions(from output: String) -> [PackageInfo] {
        var packages: [PackageInfo] = []
        let lines = output.components(separatedBy: "\n")

        LoggingUtility.shared.log("Parsing output from brew outdated")

        for line in lines {
            if line.isEmpty || line.contains("Checking for") || line.contains("Running:")
                || line.contains("==> Outdated")
            {
                continue
            }

            var packageName = ""
            var currentVersion = ""
            var availableVersion = ""
            var matched = false

            if let regex = try? NSRegularExpression(
                pattern: "^([^ ]+) \\(([^)]+)\\) (!=|\\<) ([^ \\[]+)")
            {
                let nsString = line as NSString
                let matches = regex.matches(
                    in: line, range: NSRange(location: 0, length: nsString.length))
                if let match = matches.first, match.numberOfRanges >= 5 {
                    packageName = nsString.substring(with: match.range(at: 1))
                    currentVersion = nsString.substring(with: match.range(at: 2))
                    availableVersion = nsString.substring(with: match.range(at: 4))
                    matched = true
                }
            }

            if !matched,
               let regex = try? NSRegularExpression(
                   pattern: "^([^ ]+)\\s+([^ ]+)\\s+->\\s+([^ ]+)")
            {
                let nsString = line as NSString
                let matches = regex.matches(
                    in: line, range: NSRange(location: 0, length: nsString.length))
                if let match = matches.first, match.numberOfRanges >= 4 {
                    packageName = nsString.substring(with: match.range(at: 1))
                    currentVersion = nsString.substring(with: match.range(at: 2))
                    availableVersion = nsString.substring(with: match.range(at: 3))
                    matched = true
                }
            }

            if !matched, let firstWord = line.components(separatedBy: " ").first, !firstWord.isEmpty {
                packageName = firstWord
                currentVersion = "?"
                availableVersion = "?"
                matched = true
            }

            if matched && !packageName.isEmpty {
                let packageInfo = PackageInfo(
                    name: packageName,
                    currentVersion: currentVersion,
                    availableVersion: availableVersion,
                    source: ""
                )
                packages.append(packageInfo)
            } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                LoggingUtility.shared.log("Skipping unparsed line: \(line)")
            }
        }

        LoggingUtility.shared.log(
            "Finished parsing \(packages.count) outdated packages (pre-enrichment)")
        return packages
    }

    // MARK: - Async Enrichment & Fetching

    func enrichOutdatedPackagesWithSource(packages: [PackageInfo]) async -> [PackageInfo] {
        guard !packages.isEmpty else {
            LoggingUtility.shared.log("Enrichment: No packages to enrich.")
            return []
        }

        LoggingUtility.shared.log(
            "Enrichment: Starting source enrichment for \(packages.count) packages.")

        var installedFormulae = Set<String>()
        var installedCasks = Set<String>()

        async let formulaeResult = BrewBarUtility.shared.runBrewCommand(["list", "--formula"])
        async let casksResult = BrewBarUtility.shared.runBrewCommand(["list", "--cask"])

        if let (formulaOutput, status) = try? await formulaeResult, status == 0 {
            for name in formulaOutput.split(separator: "\n") {
                installedFormulae.insert(String(name))
            }
            LoggingUtility.shared.log("Found \(installedFormulae.count) installed formulas")
        }

        if let (caskOutput, status) = try? await casksResult, status == 0 {
            for name in caskOutput.split(separator: "\n") {
                installedCasks.insert(String(name))
            }
            LoggingUtility.shared.log("Found \(installedCasks.count) installed casks")
        }

        var enrichedPackages = packages

        for i in 0 ..< enrichedPackages.count {
            let packageName = enrichedPackages[i].name

            if installedCasks.contains(packageName) {
                enrichedPackages[i].source = "cask"
            } else if installedFormulae.contains(packageName) {
                enrichedPackages[i].source = "formula"
            } else if packageName.contains("/") {
                let components = packageName.components(separatedBy: "/")
                if components.count >= 2 {
                    enrichedPackages[i].source = components[0]
                } else {
                    enrichedPackages[i].source = "formula"
                }
            } else {
                if let (_, exitCode) = try? await BrewBarUtility.shared.runBrewCommand(["info", "--cask", packageName]),
                   exitCode == 0
                {
                    enrichedPackages[i].source = "cask"
                } else {
                    enrichedPackages[i].source = "formula"
                }
            }

            LoggingUtility.shared.log(
                "Set source for '\(packageName)' to '\(enrichedPackages[i].source)'")
        }

        return enrichedPackages
    }

    func fetchInstalledPackages() async -> [InstalledPackageInfo] {
        LoggingUtility.shared.log("Fetching installed packages...")

        guard BrewBarUtility.shared.brewPath != nil else {
            LoggingUtility.shared.log("ERROR: Brew executable not found for fetching installed packages")
            return []
        }

        var installedPackages: [InstalledPackageInfo] = []

        async let formulaeResult = BrewBarUtility.shared.runBrewCommand(["list", "--versions", "--formula"])
        async let casksResult = BrewBarUtility.shared.runBrewCommand(["list", "--versions", "--cask"])

        if let (formulaeOutput, _) = try? await formulaeResult {
            let formulaeLines = formulaeOutput.components(separatedBy: "\n")
            for line in formulaeLines where !line.isEmpty {
                let components = line.components(separatedBy: " ")
                if components.count >= 2 {
                    installedPackages.append(InstalledPackageInfo(
                        name: components[0],
                        version: components[1],
                        source: "formula"
                    ))
                }
            }
            LoggingUtility.shared.log("Processed \(formulaeLines.filter { !$0.isEmpty }.count) formulae")
        }

        if let (casksOutput, _) = try? await casksResult {
            let casksLines = casksOutput.components(separatedBy: "\n")
            for line in casksLines where !line.isEmpty {
                let components = line.components(separatedBy: " ")
                if components.count >= 2 {
                    installedPackages.append(InstalledPackageInfo(
                        name: components[0],
                        version: components[1],
                        source: "cask"
                    ))
                }
            }
            LoggingUtility.shared.log("Processed \(casksLines.filter { !$0.isEmpty }.count) casks")
        }

        installedPackages.sort { $0.name < $1.name }
        LoggingUtility.shared.log("Found \(installedPackages.count) total installed packages")
        return installedPackages
    }
}
