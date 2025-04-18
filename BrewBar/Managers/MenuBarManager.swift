import Cocoa

// MARK: - Menu Bar Manager
class MenuBarManager {
    weak var appDelegate: AppDelegate?
    var statusItem: NSStatusItem?
    var menu: NSMenu?
    var outdatedPackagesMenuItem: NSMenuItem?
    var updateInProgressMenuItem: NSMenuItem?
    var nextScheduledCheckMenuItem: NSMenuItem?
    var checkIntervalSubmenu: NSMenu?
    var menuRefreshTimer: Timer?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    func setup() {
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mug", accessibilityDescription: "Homebrew Status") // Initial icon
        }

        // Create the menu
        setupMenu()
        statusItem?.menu = menu

        // Schedule the periodic menu refresh timer
        scheduleMenuRefreshTimer()
    }

    // MARK: - Menu Setup
    func setupMenu() {
        menu = NSMenu()

        outdatedPackagesMenuItem = NSMenuItem(title: "Checking for updates...", action: nil, keyEquivalent: "")
        outdatedPackagesMenuItem?.isEnabled = false // Display only
        menu?.addItem(outdatedPackagesMenuItem!)

        // -- Last Checked --
        let lastCheckedItem = NSMenuItem(title: "Last checked: Never", action: nil, keyEquivalent: "")
        lastCheckedItem.isEnabled = false // Display only
        lastCheckedItem.tag = 1001 // Tag for easy retrieval later
        menu?.addItem(lastCheckedItem)

        // -- Next Scheduled Check --
        nextScheduledCheckMenuItem = NSMenuItem(title: "Next check: Not scheduled", action: nil, keyEquivalent: "")
        nextScheduledCheckMenuItem?.isEnabled = false // Display only
        menu?.addItem(nextScheduledCheckMenuItem!)

        // -- Show Outdated Packages --
        let showOutdatedItem = NSMenuItem(title: "View Packages...", action: #selector(AppDelegate.showOutdatedPackagesWindow), keyEquivalent: "")
        showOutdatedItem.target = appDelegate
        showOutdatedItem.isEnabled = false // Initially disabled until first check completes
        menu?.addItem(showOutdatedItem)

        menu?.addItem(NSMenuItem.separator())

        // -- Check Interval Submenu --
        let checkIntervalItem = NSMenuItem(title: "Check Interval", action: nil, keyEquivalent: "")
        checkIntervalSubmenu = NSMenu()

        if let appDelegate = appDelegate {
            // Add all interval options to the submenu
            for (name, interval) in appDelegate.intervalOptions.sorted(by: { $0.value < $1.value }) {
                let intervalItem = NSMenuItem(title: name, action: #selector(AppDelegate.setIntervalFromMenu(_:)), keyEquivalent: "")
                intervalItem.target = appDelegate
                intervalItem.representedObject = interval
                // Mark the current interval
                if interval == appDelegate.getCurrentInterval() {
                    intervalItem.state = .on
                }
                checkIntervalSubmenu?.addItem(intervalItem)
            }
        }

        checkIntervalItem.submenu = checkIntervalSubmenu
        menu?.addItem(checkIntervalItem)

        //  -- Update and Upgrade --
        let updateItem = NSMenuItem(title: "Update Homebrew", action: #selector(AppDelegate.runUpdate), keyEquivalent: "u")
        updateItem.target = appDelegate
        menu?.addItem(updateItem)

        let upgradeItem = NSMenuItem(title: "Upgrade All Packages", action: #selector(AppDelegate.runUpgradeAll), keyEquivalent: "U")
        upgradeItem.target = appDelegate
        menu?.addItem(upgradeItem)

        updateInProgressMenuItem = NSMenuItem(title: "Operation in progress...", action: nil, keyEquivalent: "")
        updateInProgressMenuItem?.isHidden = true // Initially hidden
        updateInProgressMenuItem?.isEnabled = false
        menu?.addItem(updateInProgressMenuItem!)

        menu?.addItem(NSMenuItem.separator())

        //  -- Settings --
        let preferencesItem = NSMenuItem(title: "Settings...", action: #selector(AppDelegate.showPreferences), keyEquivalent: ",")
        preferencesItem.target = appDelegate
        menu?.addItem(preferencesItem)

        //  -- Version ---
        menu?.addItem(NSMenuItem.separator())
        let versionString = getAppVersionString()
        let versionItem = NSMenuItem(title: versionString, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu?.addItem(versionItem)

        //  -- GitHub --
        let githubItem = NSMenuItem(title: "View on GitHub", action: #selector(openGitHub), keyEquivalent: "")
        githubItem.target = self
        menu?.addItem(githubItem)

        menu?.addItem(NSMenuItem.separator())

        //  -- Quit --
        let quitItem = NSMenuItem(title: "Quit BrewBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu?.addItem(quitItem)

        // Update the last checked timestamp
        updateLastCheckedMenuItem()
    }

    // Get the app version for display
    private func getAppVersionString() -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        return "Version \(appVersion)"
    }

    // Schedule the timer to refresh the menu title
    func scheduleMenuRefreshTimer() {
        // Ensure no duplicate timers
        menuRefreshTimer?.invalidate()

        // Refresh every minute for accurate countdown display
        menuRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateCheckNowMenuItemTitle()
        }

        // Allow timer to run even when menu is open
        RunLoop.current.add(menuRefreshTimer!, forMode: .common)
        LoggingUtility.shared.log("Scheduled menu refresh every minute.")
    }

    // Update the last checked menu item
    func updateLastCheckedMenuItem() {
        guard let lastCheckedItem = menu?.item(withTag: 1001),
              let lastCheckTime = appDelegate?.lastCheckTime else {

            if let lastCheckedItem = menu?.item(withTag: 1001) {
                lastCheckedItem.title = "Last checked: Never"
            }
            return
        }

        // Format the timestamp
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let timeString = formatter.string(from: lastCheckTime)

        lastCheckedItem.title = "Last checked: \(timeString)"
    }

    // Update the next check menu item
    func updateNextCheckMenuItem() {
        DispatchQueue.main.async {
            guard let nextScheduledCheckMenuItem = self.nextScheduledCheckMenuItem else {
                return
            }

            if let nextCheckTime = self.appDelegate?.nextScheduledCheckTime {
                // Calculate how much time until next check
                let interval = nextCheckTime.timeIntervalSinceNow

                // Check if next check time is in the past
                if interval <= 0 {
                    nextScheduledCheckMenuItem.title = "Next check: Checking soon..."

                    // Notify app delegate that it's time to reschedule the timer
                    if let appDelegate = self.appDelegate {
                        DispatchQueue.main.async {
                            appDelegate.scheduleUpdateTimer() // This will recalculate next check time
                        }
                    }
                } else {
                    // Format the next check time
                    let formatter = DateFormatter()
                    formatter.dateStyle = .none
                    formatter.timeStyle = .short
                    let timeString = formatter.string(from: nextCheckTime)

                    // Format the time until next check
                    let timeUntil = self.formatTimeInterval(interval)

                    nextScheduledCheckMenuItem.title = "Next check: \(timeString) (\(timeUntil))"
                }
            } else {
                nextScheduledCheckMenuItem.title = "Next check: Manual only"
            }
        }
    }

    // Format a time interval in a human-readable way
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        if interval <= 0 {
            return "now"
        }

        let minutes = Int(interval / 60) % 60
        let hours = Int(interval / 3600)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    // Function to update the "Check Now" menu item title
    func updateCheckNowMenuItemTitle() {
        DispatchQueue.main.async {
            // Update the last checked timestamp
            self.updateLastCheckedMenuItem()

            // Also update the next check time
            self.updateNextCheckMenuItem()
        }
    }

    // Update menu with package information
    func updateMenu(outdatedPackages: [PackageInfo] = [], checking: Bool = false, errorOccurred: Bool = false) {
        DispatchQueue.main.async {
            self.updateInProgressMenuItem?.isHidden = true // Hide progress unless update is running

            // Update based on isUpdateRunning flag
            if let isUpdateRunning = self.appDelegate?.isUpdateRunning, isUpdateRunning {
                self.updateInProgressMenuItem?.isHidden = false
            }

            if checking {
                self.outdatedPackagesMenuItem?.title = "Checking for updates..."
                self.statusItem?.button?.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Checking Updates")
                self.outdatedPackagesMenuItem?.isHidden = false
                return
            }

            if errorOccurred {
                if let appDelegate = self.appDelegate {
                    appDelegate.lastCheckError = true // Set the error state
                }
                self.outdatedPackagesMenuItem?.title = "Error checking updates"
                self.statusItem?.button?.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Error Checking Updates")
                self.outdatedPackagesMenuItem?.isHidden = false
                self.outdatedPackagesMenuItem?.isEnabled = false
                return
            }

            // If we got here, no error occurred
            if let appDelegate = self.appDelegate {
                appDelegate.lastCheckError = false
            }

            if outdatedPackages.isEmpty {
                self.outdatedPackagesMenuItem?.title = "Homebrew is up to date"
                self.statusItem?.button?.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Homebrew Up To Date")
                self.outdatedPackagesMenuItem?.isHidden = false
                self.outdatedPackagesMenuItem?.isEnabled = false

                // Disable the show outdated packages menu item since there are no packages to show
                if let showOutdatedItem = self.menu?.item(withTitle: "View Packages...") {
                    showOutdatedItem.isEnabled = false
                }
            } else {
                let count = outdatedPackages.count
                self.statusItem?.button?.image = NSImage(systemSymbolName: "mug.fill", accessibilityDescription: "\(count) Updates Available") // Icon indicating updates

                // Truncate list for display
                // TODO: This doesn't format well
                let maxDisplay = 3
                var displayString = "\(count) outdated package\(count == 1 ? "" : "s"):\n"
                displayString += outdatedPackages.prefix(maxDisplay).map { $0.name }.joined(separator: "\n")
                if count > maxDisplay {
                    displayString += "\n...(and \(count - maxDisplay) more)"
                }
                self.outdatedPackagesMenuItem?.title = displayString
                self.outdatedPackagesMenuItem?.isHidden = false
                // Make the item non-selectable, it's just for display
                self.outdatedPackagesMenuItem?.isEnabled = false

                // Enable the show outdated packages menu item since there are packages to show
                if let showOutdatedItem = self.menu?.item(withTitle: "View Packages...") {
                    showOutdatedItem.isEnabled = true
                }
            }

            // Update the last checked timestamp
            self.updateLastCheckedMenuItem()
        }
    }

    // Clean up resources
    func cleanup() {
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = nil
    }

    // Open GitHub repository
    @objc func openGitHub() {
        // TODO: Put URL somewhere more globally accessible
        if let url = URL(string: "https://github.com/joshbeard/BrewBar") {
            NSWorkspace.shared.open(url)
        }
    }

    // Update the check interval submenu to reflect current selection
    func updateCheckIntervalSubmenu() {
        guard let appDelegate = appDelegate,
              let submenu = checkIntervalSubmenu else {
            return
        }

        let currentInterval = appDelegate.getCurrentInterval()

        // Update each menu item's state
        for item in submenu.items {
            if let itemInterval = item.representedObject as? TimeInterval {
                item.state = (itemInterval == currentInterval) ? .on : .off
            }
        }
    }

    // Rebuild the items in the check interval submenu
    func rebuildIntervalSubmenuItems() {
        guard let appDelegate = appDelegate,
              let submenu = checkIntervalSubmenu else {
            LoggingUtility.shared.log("Error: Could not rebuild interval submenu - delegate or submenu missing")
            return
        }

        LoggingUtility.shared.log("Rebuilding interval submenu items")
        submenu.removeAllItems()

        // Add all interval options to the submenu
        for (name, interval) in appDelegate.intervalOptions.sorted(by: { $0.value < $1.value }) {
            let intervalItem = NSMenuItem(title: name, action: #selector(AppDelegate.setIntervalFromMenu(_:)), keyEquivalent: "")
            intervalItem.target = appDelegate
            intervalItem.representedObject = interval
            // Mark the current interval
            if interval == appDelegate.getCurrentInterval() {
                intervalItem.state = .on
            }
            submenu.addItem(intervalItem)
        }
         LoggingUtility.shared.log("Finished rebuilding interval submenu with \(submenu.items.count) items")
    }
}