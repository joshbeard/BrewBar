import AppKit
import SwiftTerm
import SwiftUI

struct SwiftTermView: NSViewRepresentable {
    let executablePath: String
    let arguments: [String]
    /// Resolved light/dark for terminal chrome (from settings + optional system match).
    var resolvedTerminalScheme: ColorScheme
    var colorPreset: TerminalColorPreset
    var onProcessEnd: ((_ commandArgs: [String], _ exitCode: Int32?) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator

        applyTerminalTheme(to: view, scheme: resolvedTerminalScheme, preset: colorPreset)

        view.startProcess(executable: executablePath, args: arguments, environment: nil)
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        applyTerminalTheme(to: nsView, scheme: resolvedTerminalScheme, preset: colorPreset)
    }

    private func applyTerminalTheme(to view: LocalProcessTerminalView, scheme: ColorScheme, preset: TerminalColorPreset) {
        // Force AppKit appearance on the terminal subtree so catalog colors (and SwiftTerm’s
        // own drawing) don’t stay stuck to the window’s dark chrome when the user picks “Always light”.
        let appearanceName: NSAppearance.Name = scheme == .dark ? .darkAqua : .aqua
        if let appearance = NSAppearance(named: appearanceName) {
            view.appearance = appearance
            view.enclosingScrollView?.appearance = appearance
        }

        let colors = preset.colors(for: scheme)
        view.nativeBackgroundColor = colors.background
        view.nativeForegroundColor = colors.foreground
        view.enclosingScrollView?.scrollerKnobStyle = scheme == .dark ? .light : .dark
        view.needsDisplay = true
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var parent: SwiftTermView

        init(_ parent: SwiftTermView) {
            self.parent = parent
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async {
                let exitMessage: String
                if let code = exitCode {
                    let status = (code == 0) ? "successfully" : "with error code \(code)"
                    exitMessage = "\n\n[Process completed \(status)]\n"
                } else {
                    exitMessage = "\n\n[Process terminated (no exit code)]\n"
                }

                if let termView = source as? LocalProcessTerminalView {
                    let scheme = self.parent.resolvedTerminalScheme
                    let prefix = self.parent.colorPreset.exitMessageANSIPrefix(success: exitCode == 0, scheme: scheme)
                    let resetCode = "\u{001B}[0m"
                    termView.feed(text: prefix + exitMessage + resetCode)
                }

                if let code = exitCode {
                    self.parent.onProcessEnd?(self.parent.arguments, code)
                } else {
                    self.parent.onProcessEnd?(self.parent.arguments, nil)
                }
            }
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}

#if DEBUG
    struct SwiftTermView_Previews: PreviewProvider {
        static var previews: some View {
            SwiftTermView(
                executablePath: "/bin/bash",
                arguments: ["-c", "echo 'Hello from SwiftTerm!'; sleep 2; echo 'Done.'; exit 0"],
                resolvedTerminalScheme: .dark,
                colorPreset: .catppuccin
            )
            .frame(width: 600, height: 400)
        }
    }
#endif
