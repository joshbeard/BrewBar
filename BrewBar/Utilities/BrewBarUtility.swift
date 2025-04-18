import Foundation

// MARK: - Homebrew Utility

class BrewBarUtility {
    static let shared = BrewBarUtility()

    // Homebrew executable path
    let brewPath: String? = {
        // These are the common locations for Homebrew
        let commonPaths = [
            "/opt/homebrew/bin/brew",      // Apple Silicon default
            "/usr/local/bin/brew",         // Intel Mac default
            "/usr/bin/brew",               // Another possible location
            "/bin/brew",                    // Less common
        ]

        // Check if any of the common paths exist
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                print("Found brew at: \(path)")
                return path
            }
        }

        // Try using /bin/sh to run 'which brew' - more likely to work in Xcode
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "which brew"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                    print("Found brew via shell at: \(path)")
                    return path
                }
            }
        } catch {
            print("Error finding brew via shell: \(error)")
        }

        // If we still can't find it, try environment variables
        if let path = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"] {
            let brewPath = "\(path)/bin/brew"
            if FileManager.default.fileExists(atPath: brewPath) {
                print("Found brew from HOMEBREW_PREFIX at: \(brewPath)")
                return brewPath
            }
        }

        print("⚠️ Warning: Could not find brew executable")
        return nil
    }()

    // Helper for formatting relative time
    let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full // Use full units instead of abbreviated
        return formatter
    }()

    // Helper method to run brew commands and get the output
    func runBrewCommand(_ arguments: [String], completion: @escaping (String?, Int32, Error?) -> Void) {
        guard let brewExec = brewPath else {
            completion(nil, -1, NSError(domain: "BrewBar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Brew executable not found"]))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: brewExec)
            task.arguments = arguments

            let outputPipe = Pipe()
            task.standardOutput = outputPipe

            do {
                try task.run()
                task.waitUntilExit()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8)

                DispatchQueue.main.async {
                    completion(output, task.terminationStatus, nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(nil, -1, error)
                }
            }
        }
    }

    // Helper method to run brew commands in Terminal.app for interactive commands
    func runInteractiveBrewCommand(_ args: [String]) {
        guard let brewExec = brewPath else {
            LoggingUtility.shared.log("ERROR: Brew executable not found")
            return
        }

        // Create a temporary shell script to run our command
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("brewbar-command.sh")

        // Build the script content
        let brewCommand = "\(brewExec) \(args.joined(separator: " "))"
        let scriptContent = """
            #!/bin/bash
            set -e

            # Function to clean up the temp script
            cleanup() {
                rm -f "\(scriptPath.path)"
            }

            # Set up trap to clean up on exit
            trap cleanup EXIT

            # Clear the screen and show header
            clear
            echo "=== BrewBar Command ==="
            echo "Running: \(brewCommand)"
            echo "===================="
            echo

            # Run the actual command and capture its exit status
            set +e
            \(brewCommand) 2>&1
            STATUS=$?
            set -e

            echo
            if [ $STATUS -eq 0 ]; then
                echo "✅ Command completed successfully (exit code: $STATUS)"
            else
                echo "❌ Command failed (exit code: $STATUS)"
            fi

            echo
            read -p "Press return to close this window..."

            # Exit with the command's status
            exit $STATUS
            """

        do {
            // Write the script
            try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

            // Create the command to open Terminal and execute our script
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [
                "-a", "Terminal",
                scriptPath.path,
            ]

            LoggingUtility.shared.log("Running brew command in Terminal: \(brewCommand)")
            try task.run()

        } catch {
            LoggingUtility.shared.log("Error setting up Terminal command: \(error.localizedDescription)")
        }
    }
}
