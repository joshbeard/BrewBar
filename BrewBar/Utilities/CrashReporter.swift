import Foundation

// MARK: - Crash Reporting
// Global function for uncaught exceptions (required for C function compatibility)
func handleUncaughtException(_ exception: NSException) {
    let stack = exception.callStackSymbols.joined(separator: "\n")
    let reason = exception.reason ?? "No reason provided"
    let name = exception.name.rawValue

    LoggingUtility.shared.log("CRASH: \(name) - \(reason)")
    LoggingUtility.shared.log("Stack trace:\n\(stack)")

    // Save crash report
    CrashReporter.shared.saveCrashReport(name: name, reason: reason, stack: stack)
}

class CrashReporter {
    static let shared = CrashReporter()

    func setup() {
        // Set up a global exception handler using a C-compatible function reference
        NSSetUncaughtExceptionHandler(handleUncaughtException)
    }

    func saveCrashReport(name: String, reason: String, stack: String) {
        let fileManager = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let dateString = formatter.string(from: Date())

        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let crashesDir = appSupportDir.appendingPathComponent("BrewBar/Crashes")

        do {
            if !fileManager.fileExists(atPath: crashesDir.path) {
                try fileManager.createDirectory(at: crashesDir, withIntermediateDirectories: true)
            }

            let crashFile = crashesDir.appendingPathComponent("crash-\(dateString).log")

            var appVersion = "Unknown"
            var buildNumber = "Unknown"
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                appVersion = version
            }
            if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                buildNumber = build
            }

            let systemVersion = ProcessInfo.processInfo.operatingSystemVersionString

            let crashReport = """
            BrewBar Crash Report
            Version: \(appVersion) (\(buildNumber))
            System: \(systemVersion)
            Date: \(DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .full))

            Exception: \(name)
            Reason: \(reason)

            Stack Trace:
            \(stack)
            """

            try crashReport.write(to: crashFile, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save crash report: \(error)")
        }
    }
}