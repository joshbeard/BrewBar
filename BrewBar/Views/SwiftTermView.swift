import SwiftUI
import SwiftTerm

struct SwiftTermView: NSViewRepresentable {
    // Properties to configure the command to run
    let executablePath: String
    let arguments: [String]
    // Callback for when the hosted process terminates.
    var onProcessEnd: ((_ commandArgs: [String], _ exitCode: Int32?) -> Void)? = nil

    // Observe the SwiftUI color scheme environment
    @Environment(\.colorScheme) var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        // Set the coordinator as the *process* delegate
        view.processDelegate = context.coordinator

        // Apply initial color scheme
        applyColorScheme(to: view, scheme: context.environment.colorScheme)

        // Start the specified process
        view.startProcess(executable: executablePath, args: arguments, environment: nil)
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Update theme if system appearance changes
        applyColorScheme(to: nsView, scheme: colorScheme)
    }

    // Applies current theme (Dracula Dark / System Light) to the terminal view.
    private func applyColorScheme(to view: LocalProcessTerminalView, scheme: ColorScheme) {
        let draculaBackground = NSColor(red: 0.16, green: 0.16, blue: 0.21, alpha: 1.0) // #282a36
        let draculaForeground = NSColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1.0) // #f8f8f2
        let lightBackground = NSColor.windowBackgroundColor
        let lightForeground = NSColor.textColor

        // Check if update is needed
        let currentBg = view.nativeBackgroundColor
        let needsUpdate: Bool
        if scheme == .dark {
            needsUpdate = (currentBg != draculaBackground)
        } else {
            needsUpdate = (currentBg != lightBackground)
        }

        if !needsUpdate { return }

        LoggingUtility.shared.log("Applying color scheme: \(scheme == .dark ? "Dracula Dark" : "System Light")")

        if scheme == .dark {
            // --- Apply Dracula Dark Theme (Base Colors Only) ---
            view.nativeForegroundColor = draculaForeground
            view.nativeBackgroundColor = draculaBackground
            view.enclosingScrollView?.scrollerKnobStyle = .light
        } else {
            // --- Apply Standard System Light Theme ---
             view.nativeForegroundColor = lightForeground
             view.nativeBackgroundColor = lightBackground
             view.enclosingScrollView?.scrollerKnobStyle = .dark
        }
         view.needsDisplay = true
    }

    // Coordinator acts as the delegate for process-related events.
    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var parent: SwiftTermView

        init(_ parent: SwiftTermView) {
            self.parent = parent
        }

        // Called when the process running in the terminal exits.
        func processTerminated(source: TerminalView, exitCode: Int32?) {
            // The source here is documented as TerminalView in the protocol,
            // but in practice for LocalProcessTerminalView, it should be itself.
            DispatchQueue.main.async {
                let exitMessage: String
                if let code = exitCode {
                    let status = (code == 0) ? "successfully" : "with error code \(code)"
                    exitMessage = "\n\n[Process completed \(status)]\n"
                    // Call the updated callback with arguments and exit code
                    self.parent.onProcessEnd?(self.parent.arguments, code)
                } else {
                    // This might happen if the process was terminated by a signal
                    exitMessage = "\n\n[Process terminated (no exit code)]\n"
                    self.parent.onProcessEnd?(self.parent.arguments, nil)
                }

                // Display completion message in the terminal view.
                if let termView = source as? LocalProcessTerminalView {
                    // Use a different color for the status message
                    // ANSI escape code for bright green: \u{001B}[92m
                    // ANSI escape code for bright red:   \u{001B}[91m
                    // ANSI escape code to reset:       \u{001B}[0m
                    let colorCode = (exitCode == 0) ? "\u{001B}[92m" : "\u{001B}[91m"
                    let resetCode = "\u{001B}[0m"
                    termView.feed(text: colorCode + exitMessage + resetCode)
                }
            }
        }

        // Other LocalProcessTerminalViewDelegate methods (if any are required - checking the protocol definition provided)
        // Based on the provided code, these seem to be the relevant ones from the protocol definition:
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // We likely don't need to do anything here unless our SwiftUI view needs to react
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            // We could potentially update the window title here if desired
             // For example: parent.window?.title = title
        }

        func hostCurrentDirectoryUpdate (source: TerminalView, directory: String?) {
             // Could use this to display the current PWD somewhere if needed
        }
    }
}

// Preview provider - requires a valid executable path
#if DEBUG
struct SwiftTermView_Previews: PreviewProvider {
    static var previews: some View {
        SwiftTermView(executablePath: "/bin/bash", arguments: ["-c", "echo 'Hello from SwiftTerm!'; sleep 2; echo 'Done.'; exit 0"])
            .frame(width: 600, height: 400)
    }
}
#endif