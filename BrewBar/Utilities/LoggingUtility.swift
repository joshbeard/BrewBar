import Foundation

// MARK: - Logging Utilities
class LoggingUtility {
    static let shared = LoggingUtility()

    // Number of days to keep logs
    private let logRetentionDays = 5

    static var logDirectoryURL: URL {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupportURL.appendingPathComponent("BrewBar/Logs", isDirectory: true)
    }

    private func ensureLogDirectoryExists() {
        let fileManager = FileManager.default

        // Get the Application Support directory
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("Unable to access Application Support directory")
            return
        }

        // Create the logs directory if it doesn't exist
        let logsDir = appSupportDir.appendingPathComponent("BrewBar/Logs")
        if !fileManager.fileExists(atPath: logsDir.path) {
            do {
                try fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
            } catch {
                print("Failed to create logs directory: \(error)")
            }
        }
    }

    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)] \(message)")

        // Also log to a file for debugging outside Xcode
        logToFile(message)
    }

    func logToFile(_ message: String) {
        let fileManager = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())

        // Get the logs directory in Application Support
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("Failed to get Application Support directory")
            return
        }

        let logsDir = appSupportDir.appendingPathComponent("BrewBar/Logs")

        // Create logs directory if it doesn't exist
        do {
            if !fileManager.fileExists(atPath: logsDir.path) {
                try fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
            }

            // Create or append to log file
            let logFile = logsDir.appendingPathComponent("brewbar-\(dateString).log")
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let timeString = formatter.string(from: Date())

            let logLine = "[\(timeString)] \(message)\n"

            if fileManager.fileExists(atPath: logFile.path) {
                // Append to existing file
                let fileHandle = try FileHandle(forWritingTo: logFile)
                fileHandle.seekToEndOfFile()
                if let data = logLine.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                // Create new file
                try logLine.write(to: logFile, atomically: true, encoding: .utf8)
            }
        } catch {
            print("Failed to write to log file: \(error)")
        }
    }

    func performLogMaintenance() {
        cleanupOldLogs()
    }

    func cleanupOldLogs() {
        let fileManager = FileManager.default
        let logsDir = Self.logDirectoryURL

        // Get the cutoff date (5 days ago)
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -logRetentionDays, to: Date()) else {
            print("Failed to calculate cutoff date")
            return
        }

        do {
            // Get all log files in the directory
            let logFiles = try fileManager.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil)

            // Date formatter to parse dates from filenames
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"

            for fileURL in logFiles {
                // Extract date from filename (format: brewbar-YYYY-MM-DD.log)
                let filename = fileURL.lastPathComponent
                guard filename.hasPrefix("brewbar-"),
                      filename.hasSuffix(".log") else {
                    continue
                }

                let dateString = filename.replacingOccurrences(of: "brewbar-", with: "").replacingOccurrences(of: ".log", with: "")
                guard let fileDate = formatter.date(from: dateString) else {
                    continue
                }

                if fileDate < cutoffDate {
                    try fileManager.removeItem(at: fileURL)
                    print("Deleted old log file: \(filename)")
                }
            }
        } catch {
            print("Error cleaning up log files: \(error)")
        }
    }
}