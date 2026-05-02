import AppKit

// MARK: - AppDelegate (Minimal Adapter)

// Core logic lives in AppState. This handles NSApp lifecycle and NSWindowDelegate.

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let appState = AppState.shared

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = NotificationManager.shared
        NotificationManager.shared.configure()
        appState.startup()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(anyWindowDidClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func anyWindowDidClose(_ notification: Notification) {
        hideFromDockIfNoWindows()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        appState.cleanup()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === appState.outdatedPackagesWindowController?.window,
           appState.isPackagesWindowBrewTaskRunning
        {
            appState.requestPackagesWindowCloseConfirmation()
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) == appState.outdatedPackagesWindowController?.window {
            LoggingUtility.shared.log("Outdated packages window closed.")
            appState.outdatedPackagesWindowController = nil
            appState.isPackagesWindowBrewTaskRunning = false
        }
    }

    /// Switch back to accessory (menu-bar-only) when no visible windows remain.
    private func hideFromDockIfNoWindows() {
        DispatchQueue.main.async {
            if !DockVisibility.hasVisibleForegroundWindow() {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    // MARK: - Wake from Sleep

    @objc func handleWakeFromSleep() {
        appState.handleWakeFromSleep()
    }
}
