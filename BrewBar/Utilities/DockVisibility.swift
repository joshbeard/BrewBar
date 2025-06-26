import AppKit

/// BrewBar is normally a menu-bar-only app (`LSUIElement` + `.accessory`). When Settings or the
/// packages window is shown, we promote to `.regular` so the Dock icon appears and activation works.
enum DockVisibility {
    /// Switch to a normal Dock app, unhide, and activate. Optionally key a specific window.
    static func promoteToRegularApp(keyWindow: NSWindow? = nil) {
        let apply = {
            // Unhide before changing policy — agent / `LSUIElement` apps often need this order for a successful transition.
            NSApp.unhide(nil)
            let prior = NSApp.activationPolicy()
            if prior != .regular, !NSApp.setActivationPolicy(.regular) {
                LoggingUtility.shared.log(
                    "DockVisibility: setActivationPolicy(.regular) returned false (priorPolicy=\(prior.rawValue) isHidden=\(NSApp.isHidden) windowCount=\(NSApp.windows.count))"
                )
            }
            keyWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    /// True if any window should keep us in `.regular` (visible UI other than status items).
    static func hasVisibleForegroundWindow() -> Bool {
        NSApp.windows.contains { window in
            window.isVisible
                && !window.className.contains("StatusBar")
                && window.level != .statusBar
        }
    }
}
