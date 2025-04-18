import Cocoa
import ServiceManagement
import SwiftTerm
import SwiftUI
import UserNotifications

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // Managers
    var menuBarManager: MenuBarManager!
    private var terminalWindowController: TerminalWindowController? // For non-interactive output
    private var preferencesWindowController: PreferencesWindowController?
    private var embeddedTerminalWindowController: NSWindowController? // For interactive SwiftTerm view

    // Timer for checking updates
    private var updateTimer: Timer?

    // State tracking
    var isUpdateRunning = false
    var currentOutdatedPackages: [PackageInfo] = []
    var currentInstalledPackages: [InstalledPackageInfo] = []
    var lastCheckTime: Date?
    var nextScheduledCheckTime: Date?
    var lastOutdatedCount: Int = 0
    var lastCheckError: Bool = false

    // Controller for the packages window
    var outdatedPackagesWindowController: NSWindowController?

    // App version tracking for relaunch prompt
    private var initialAppVersion: String?
    private var appBundleIdentifier: String? // Or Homebrew formula/cask name

    // UserDefaults keys
    let intervalDefaultsKey = "updateCheckInterval"
    let customIntervalsKey = "customIntervals"
    let loginItemEnabledKey = "loginItemEnabled"

    let defaultInterval: TimeInterval = 86400 // 1 day

    // Default intervals (in seconds)
    var intervalOptions: [String: TimeInterval] {
        // Combine default intervals with any custom ones
        var options: [String: TimeInterval] = [
            "Every Hour": 60 * 60,
            "Every 6 Hours": 6 * 60 * 60,
            "Every Day": 24 * 60 * 60,
            "Every Week": 7 * 24 * 60 * 60,
            "Manually": 0 // Use 0 for manual checks
        ]

        // Add any custom intervals from UserDefaults
        if let customIntervals = UserDefaults.standard.dictionary(forKey: customIntervalsKey) as? [String: TimeInterval] {
            for (name, interval) in customIntervals {
                // Don't override built-in intervals with custom ones
                if !options.keys.contains(name) {
                    options[name] = interval
                }
            }
        }

        return options
    }

    // Notification Names
    static let runCheckInSheetNotification = Notification.Name("me.joshbeard.brewbar.runCheckInSheet")
    static let runUpdateInSheetNotification = Notification.Name("me.joshbeard.brewbar.runUpdateInSheet") // For brew update
    static let runUpgradeAllInSheetNotification = Notification.Name("me.joshbeard.brewbar.runUpgradeAllInSheet") // For brew upgrade

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up crash reporting
        CrashReporter.shared.setup()

        // Set up the menu bar
        menuBarManager = MenuBarManager(appDelegate: self)
        menuBarManager.setup()

        // Create the terminal window controller
        terminalWindowController = TerminalWindowController()

        // Get initial app version and bundle ID
        initialAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        appBundleIdentifier = "brewbar"

        // Start initial data load
        checkForUpdates(displayOutput: false) { [weak self] in
            guard let self else { return }
            self.refreshInstalledPackages {
                self.scheduleUpdateTimer()
                // Final UI update after all initial loading
                self.menuBarManager.updateMenu(outdatedPackages: self.currentOutdatedPackages,
                                               checking: false,
                                               errorOccurred: self.lastCheckError)
            }
        }

        // Perform log maintenance
        LoggingUtility.shared.performLogMaintenance()

        // Register for notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showOutdatedPackagesWindow),
            name: NSNotification.Name("ShowOutdatedPackagesWindow"),
            object: nil
        )

        // Hide dock icon and prevent app from showing in the dock or app switcher
        NSApp.setActivationPolicy(.accessory)

        // Start with logging app version and environment
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        LoggingUtility.shared.log("BrewBar v\(appVersion) (\(buildNumber)) starting up")
        LoggingUtility.shared.log("System: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        LoggingUtility.shared.log("Brew path: \(BrewBarUtility.shared.brewPath ?? "Not found")")

        // Configure login item based on preferences
        configureLoginItem()

        // Setup wake from sleep notification
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Clean up timers and potentially running background tasks
        BrewBarManager.shared.updateCheckTask?.interrupt()
        updateTimer?.invalidate()
        menuBarManager.cleanup()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Timer Scheduling & Interval Handling

    func scheduleUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
        let interval = getCurrentInterval()

        if interval > 0 {
            // Calculate next check time - always use current time as base
            let nextCheck = Date().addingTimeInterval(interval)
            nextScheduledCheckTime = nextCheck

            // Create a new timer starting from now
            updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                guard let self else { return }

                // Perform log maintenance
                LoggingUtility.shared.performLogMaintenance()

                // Always run update on scheduled checks
                self.checkForUpdates(runUpdate: true) {
                    // Reschedule timer after check is complete to ensure next time is always in the future
                    self.scheduleUpdateTimer()
                }
            }

            LoggingUtility.shared.log("Scheduled update check every \(interval) seconds. Next check at \(formatDate(nextCheck))")
            menuBarManager.updateNextCheckMenuItem()
            // Call updateMenu after scheduling to ensure consistency
            menuBarManager.updateMenu(outdatedPackages: currentOutdatedPackages, checking: false, errorOccurred: lastCheckError)
        } else {
            nextScheduledCheckTime = nil
            LoggingUtility.shared.log("Update checks set to manual.")
            menuBarManager.updateNextCheckMenuItem()
            // Call updateMenu after setting to manual
            menuBarManager.updateMenu(outdatedPackages: currentOutdatedPackages, checking: false, errorOccurred: lastCheckError)
        }
    }

    func getCurrentInterval() -> TimeInterval {
        let savedInterval = UserDefaults.standard.double(forKey: intervalDefaultsKey)

        // Check if the interval has never been set
        if UserDefaults.standard.object(forKey: intervalDefaultsKey) == nil {
            // Set the default to daily (86400 seconds)
            UserDefaults.standard.set(defaultInterval, forKey: intervalDefaultsKey)
            return defaultInterval
        }

        // Check if the saved value exists among our predefined intervals
        if intervalOptions.values.contains(savedInterval) {
            return savedInterval
        } else {
            // If not found, save and return the default
            UserDefaults.standard.set(defaultInterval, forKey: intervalDefaultsKey)
            return defaultInterval
        }
    }

    @objc func setInterval(_ sender: NSPopUpButton) {
        guard let selectedItem = sender.selectedItem,
              let interval = selectedItem.representedObject as? TimeInterval
        else {
            return
        }

        // Save the selected interval to UserDefaults
        UserDefaults.standard.set(interval, forKey: intervalDefaultsKey)

        // Reschedule the timer with the new interval
        scheduleUpdateTimer()

        // Update the menubar submenu to reflect the change
        menuBarManager.updateCheckIntervalSubmenu()
        menuBarManager.rebuildIntervalSubmenuItems()

        // Post notification for other interested views
        NotificationCenter.default.post(name: NSNotification.Name("IntervalChanged"), object: nil)
    }

    // Method for handling interval selection from the menubar submenu
    @objc func setIntervalFromMenu(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else {
            return
        }

        // Save the selected interval to UserDefaults
        UserDefaults.standard.set(interval, forKey: intervalDefaultsKey)

        // Reschedule the timer with the new interval
        scheduleUpdateTimer()

        // Update the menubar submenu to reflect the change
        menuBarManager.updateCheckIntervalSubmenu()
        menuBarManager.rebuildIntervalSubmenuItems()

        // Post notification for other interested views
        NotificationCenter.default.post(name: NSNotification.Name("IntervalChanged"), object: nil)
    }

    // MARK: - Login Item Configuration

    func configureLoginItem() {
        // Get the saved preference, default to true if not set
        let enabled = UserDefaults.standard.object(forKey: loginItemEnabledKey) != nil
            ? UserDefaults.standard.bool(forKey: loginItemEnabledKey)
            : true

        // Configure the login item
        LoginItemUtility.setLoginItemEnabled(enabled)
    }

    @objc func toggleLoginItem(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: loginItemEnabledKey)
        LoginItemUtility.setLoginItemEnabled(enabled)
    }

    func isLoginItemEnabled() -> Bool {
        return LoginItemUtility.isLoginItemEnabled()
    }

    // MARK: - Outdated Packages Window

    @objc func showOutdatedPackagesWindow() {
        // Check if window already exists and bring it to front
        if let existingController = outdatedPackagesWindowController,
           let window = existingController.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // If the menu item was used, post notification to ensure sheet opens
            // (Consider if this is needed or if just bringing window forward is enough)
            // NotificationCenter.default.post(name: Self.runCheckInSheetNotification, object: nil)
            return
        }

        LoggingUtility.shared.log("Creating packages window...")
        let viewState = PackageViewState()

        // Create the initial view - Removed checkNow parameter
        let initialView = OutdatedPackagesView(
            packages: currentOutdatedPackages,
            installed: [],
            errorOccurred: lastCheckError,
            viewState: viewState,
            // Updated refreshDataAfterTask closure
            refreshDataAfterTask: { [weak self] commandArgs, exitCode in
                self?.handleTaskCompletion(commandArgs: commandArgs, exitCode: exitCode)
            }
        )

        // Create a hosting controller
        let hostingController = NSHostingController(rootView: initialView)

        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 550),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 600, height: 450)
        window.center()
        window.setFrameAutosaveName("OutdatedPackagesWindow")
        window.contentViewController = hostingController
        window.title = "Homebrew Packages"
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Create and store window controller
        outdatedPackagesWindowController = NSWindowController(window: window)

        // Show the window
        outdatedPackagesWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Fetch installed packages and update the view asynchronously
        BrewBarManager.shared.fetchInstalledPackages { [weak self, weak viewState] packages in
            guard let self else { return }
            guard let capturedViewState = viewState else { return }
            guard let window = self.outdatedPackagesWindowController?.window,
                  let contentVC = window.contentViewController as? NSHostingController<OutdatedPackagesView> else { return }

            let updatedView = OutdatedPackagesView(
                packages: self.currentOutdatedPackages,
                installed: packages,
                errorOccurred: self.lastCheckError,
                viewState: capturedViewState,
                refreshDataAfterTask: { [weak self] commandArgs, exitCode in
                    self?.handleTaskCompletion(commandArgs: commandArgs, exitCode: exitCode)
                }
            )
            contentVC.rootView = updatedView
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Only handle closing the packages window now
        if (notification.object as? NSWindow) == outdatedPackagesWindowController?.window {
            LoggingUtility.shared.log("Outdated packages window closed.")
            outdatedPackagesWindowController = nil
        }
        // Check if the closing window is our embedded terminal window
        else if (notification.object as? NSWindow) == embeddedTerminalWindowController?.window {
            LoggingUtility.shared.log("Embedded terminal window closed.")
            // Optional: Interrupt process when window closes (TBD)
            // Remove the attempt to interrupt the internal process.
            /*
             if let hostingController = embeddedTerminalWindowController?.window?.contentViewController as? NSHostingController<SwiftTermView>,
                let terminalView = hostingController.view as? LocalProcessTerminalView {
                 LoggingUtility.shared.log("Interrupting embedded terminal process on window close.")
                 // terminalView.process?.interrupt() // Don't do this
             }
             */
            embeddedTerminalWindowController = nil // Release the controller reference

            // Trigger a refresh check after closing the terminal, as the user likely changed something
            LoggingUtility.shared.log("Triggering background check after embedded terminal closed.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { // Short delay
                self.checkForUpdates(displayOutput: false) { // Run check silently
                    self.refreshInstalledPackages()
                }
            }
        }
    }

    // MARK: - Menu Item Actions (Triggering Sheet via Notifications)

    @objc func checkForUpdatesManual() {
        // Rate limiting logic remains the same...
        if let lastCheck = lastCheckTime, Date().timeIntervalSince(lastCheck) < 60 {
            // ... show alert ...
            return
        }

        LoggingUtility.shared.log("Manual update check triggered from menu.")

        // 1. Ensure the packages window is open and frontmost
        showOutdatedPackagesWindow()

        // 2. Post notification to tell the window to show the check in its sheet
        // Needs a slight delay to ensure window is ready to receive if just created
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Always run brew update first for manual checks
            NotificationCenter.default.post(name: Self.runUpdateInSheetNotification, object: nil)
        }
    }

    @objc func runUpdate() {
        LoggingUtility.shared.log("Update DB triggered from menu.")
        showOutdatedPackagesWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: Self.runUpdateInSheetNotification, object: nil)
        }
    }

    @objc func runUpgradeAll() {
        LoggingUtility.shared.log("Upgrade All triggered from menu.")
        showOutdatedPackagesWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: Self.runUpgradeAllInSheetNotification, object: nil)
        }
    }

    // MARK: - Background Check Logic

    func checkForUpdates(displayOutput: Bool = false, runUpdate: Bool = false, completion: (() -> Void)? = nil) {
        // Ignore displayOutput=true branch as it's handled via notifications
        if displayOutput {
            LoggingUtility.shared.log("Warning: checkForUpdates(displayOutput: true) called directly. Manual checks should use checkForUpdatesManual().")
            DispatchQueue.main.async { completion?() }
            return
        }

        // Prevent overlapping checks
        if BrewBarManager.shared.updateCheckTask != nil {
            LoggingUtility.shared.log("Background check already in progress. Skipping.")
            DispatchQueue.main.async { completion?() } // Still call completion
            return
        }

        lastCheckError = false
        menuBarManager.updateMenu(checking: true) // Update UI to show checking
        LoggingUtility.shared.log("Starting background check...")

        // If running update first, do that, then check outdated packages
        if runUpdate {
            // Use BrewBarManager's update command
            let updateCommand = BrewBarManager.shared.updateCommand
            LoggingUtility.shared.log("Running brew update: \(updateCommand.joined(separator: " "))")

            // Use the utility method to run the command
            BrewBarUtility.shared.runBrewCommand(updateCommand) { [weak self] _, exitCode, error in
                guard let self else {
                    completion?()
                    return
                }

                if error != nil || exitCode != 0 {
                    LoggingUtility.shared.log("Brew update failed with error: \(error?.localizedDescription ?? "Exit code: \(exitCode)")")
                } else {
                    LoggingUtility.shared.log("Brew update completed successfully")
                }

                // Proceed to check for outdated packages regardless of update success
                self.checkForOutdatedPackages(completion: completion)
            }
        } else {
            // Just check for outdated packages directly
            checkForOutdatedPackages(completion: completion)
        }
    }

    // Helper method to check for outdated packages
    private func checkForOutdatedPackages(completion: (() -> Void)? = nil) {
        // Run the outdated command
        BrewBarUtility.shared.runBrewCommand(["outdated", "--verbose"]) { [weak self] output, exitCode, error in
            guard let self else {
                DispatchQueue.main.async { completion?() }
                return
            }

            DispatchQueue.main.async {
                self.lastCheckTime = Date()
                self.menuBarManager.updateCheckNowMenuItemTitle()

                if let error {
                    LoggingUtility.shared.log("Error checking for outdated packages: \(error.localizedDescription)")
                    self.lastCheckError = true
                    self.menuBarManager.updateMenu(outdatedPackages: [], checking: false, errorOccurred: true)
                    completion?()
                    return
                }

                // Process the output to find outdated packages
                let packages: [PackageInfo]
                let encounteredError: Bool

                if exitCode == 0 {
                    if let output {
                        packages = BrewBarManager.shared.parsePackagesWithVersions(from: output)
                        LoggingUtility.shared.log("Background check found \(packages.count) outdated packages")
                        let currentCount = packages.count
                        if currentCount > 0 && self.lastOutdatedCount == 0 {
                            NotificationManager.shared.sendNotification(count: currentCount)
                        }
                        self.lastOutdatedCount = currentCount
                        self.lastCheckError = false
                        encounteredError = false
                    } else {
                        LoggingUtility.shared.log("No output from outdated command despite success code")
                        packages = []
                        encounteredError = true
                        self.lastCheckError = true
                    }
                } else {
                    let logMessage = "Error in background check (status \(exitCode)): \(output ?? "No output")"
                    LoggingUtility.shared.log(logMessage)
                    packages = []
                    encounteredError = true
                    self.lastCheckError = true
                }

                // Enrich the packages with additional information
                BrewBarManager.shared.enrichOutdatedPackagesWithSource(packages: packages) { [weak self] enrichedPackages in
                    guard let self else {
                        DispatchQueue.main.async { completion?() }
                        return
                    }

                    self.currentOutdatedPackages = enrichedPackages
                    self.menuBarManager.updateMenu(outdatedPackages: enrichedPackages,
                                                   checking: false,
                                                   errorOccurred: encounteredError)

                    // Re-enable menu items if needed
                    if let showOutdatedItem = self.menuBarManager.menu?.item(withTitle: "View Packages...") {
                        showOutdatedItem.isEnabled = true
                    }

                    completion?()
                }
            }
        }
    }

    // MARK: - State Update Helpers

    func updateMenuWithError() {
        lastCheckError = true
        menuBarManager.updateMenu(errorOccurred: true)
    }

    // Called by BrewBarManager if background task is started/stopped elsewhere (if applicable)
    func updateMenuWithUpdateStatus() {
        menuBarManager.updateInProgressMenuItem?.isHidden = !isUpdateRunning
    }

    // Refreshes installed packages list asynchronously.
    func refreshInstalledPackages(completion: (() -> Void)? = nil) {
        LoggingUtility.shared.log("Fetching installed packages")
        BrewBarManager.shared.fetchInstalledPackages { [weak self] packages in
            guard let self else { return }
            self.currentInstalledPackages = packages
            LoggingUtility.shared.log("Found \(packages.count) installed packages")
            completion?()
        }
    }

    // Refreshes the content of the packages window if it's open.
    private func refreshPackagesWindow(viewState: PackageViewState? = nil) {
        guard let windowController = outdatedPackagesWindowController,
              let window = windowController.window,
              let contentVC = window.contentViewController as? NSHostingController<OutdatedPackagesView>
        else {
            // Window is likely closed, nothing to refresh
            return
        }

        // Determine the correct view state to use
        let currentViewState = viewState ?? contentVC.rootView.viewState

        // Create updated view - Add back missing arguments
        let updatedView = OutdatedPackagesView(
            packages: currentOutdatedPackages, // Pass current outdated packages
            installed: currentInstalledPackages, // Pass current installed packages
            errorOccurred: lastCheckError,
            viewState: currentViewState, // Use the determined state
            // Only pass required callback
            refreshDataAfterTask: { [weak self] commandArgs, exitCode in
                self?.handleTaskCompletion(commandArgs: commandArgs, exitCode: exitCode)
            }
        )

        // Update the content view
        contentVC.rootView = updatedView
    }

    // Handles completion of tasks run in the sheet, performs optimistic UI updates.
    private func handleTaskCompletion(commandArgs: [String], exitCode: Int32?) {
        guard let exitCode else {
            LoggingUtility.shared.log("Task completed with no exit code (terminated via signal?). Triggering full refresh.")
            triggerFullBackgroundRefresh()
            return
        }

        if exitCode == 0 {
            LoggingUtility.shared.log("Task \(commandArgs.joined(separator: " ")) completed successfully.")
            var needsOptimisticRefresh = false
            var wasUpgradeAll = false

            // Check for specific command types eligible for optimistic update
            if commandArgs.first == "upgrade" && commandArgs.count > 1 {
                // Specific package upgrade: remove from outdated list
                let upgradedPackages = commandArgs.dropFirst()
                currentOutdatedPackages.removeAll { upgradedPackages.contains($0.name) }
                LoggingUtility.shared.log("Optimistic update: Removed \(upgradedPackages.joined(separator: ", ")) from outdated list.")
                needsOptimisticRefresh = true
                // Check if this app was specifically upgraded
                if let bundleId = appBundleIdentifier, upgradedPackages.contains(bundleId) {
                    checkIfAppWasUpdated() // Check version after specific upgrade
                }

            } else if commandArgs.first == "uninstall" && commandArgs.count > 1 {
                // Uninstall specific package: remove from installed list
                let packageNameIndex = commandArgs.firstIndex(where: { !$0.starts(with: "-") && $0 != "uninstall" }) ?? (commandArgs.count - 1)
                if packageNameIndex < commandArgs.count { // Ensure index is valid
                    let packageName = commandArgs[packageNameIndex]
                    currentInstalledPackages.removeAll { $0.name == packageName }
                    // Also remove from outdated if it was there
                    currentOutdatedPackages.removeAll { $0.name == packageName }
                    LoggingUtility.shared.log("Optimistic update: Removed \(packageName) from installed/outdated lists.")
                    needsOptimisticRefresh = true
                }
            }
            // --- No optimistic update for 'brew update' or 'brew upgrade' (all) ---
            // These require a full background check afterwards.
            else if commandArgs.first == "update" || (commandArgs.first == "upgrade" && commandArgs.count == 1) {
                LoggingUtility.shared.log("'\(commandArgs.first ?? "")' command finished. Triggering full background refresh.")
                if commandArgs.first == "upgrade" {
                    wasUpgradeAll = true // Mark that upgrade all was run
                }
                triggerFullBackgroundRefresh() // Refresh data immediately
                needsOptimisticRefresh = false // Don't do optimistic refresh for these
            }

            // Perform optimistic refresh if flag is set
            if needsOptimisticRefresh {
                DispatchQueue.main.async {
                    self.refreshPackagesWindow()
                }
            }

            // Check for app update *after* upgrade-all refresh is triggered
            if wasUpgradeAll {
                checkIfAppWasUpdated()
            }

        } else {
            // Command failed
            LoggingUtility.shared.log("Task \(commandArgs.joined(separator: " ")) failed with exit code \(exitCode). Triggering full refresh.")
            // Trigger full refresh on failure to ensure UI consistency
            triggerFullBackgroundRefresh()
        }

        // Ensure UI is always updated
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }

            self.checkForUpdates(displayOutput: false) { [weak self] in
                guard let self else { return }

                self.refreshInstalledPackages {
                    // Force refresh UI after data updates
                    self.refreshPackagesWindow()

                    // Important: Reschedule the timer to ensure next check time is updated
                    self.scheduleUpdateTimer()

                    // Then update the menu
                    self.menuBarManager.updateMenu(outdatedPackages: self.currentOutdatedPackages,
                                                   checking: false,
                                                   errorOccurred: self.lastCheckError)
                }
            }
        }
    }

    // Triggers a full background data refresh.
    private func triggerFullBackgroundRefresh() {
        self.checkForUpdates(displayOutput: false) { [weak self] in
            self?.refreshInstalledPackages()
        }
    }

    // MARK: - App Update Check & Relaunch

    private func checkIfAppWasUpdated() {
        guard let bundleId = appBundleIdentifier, let initialVersion = initialAppVersion, initialVersion != "Unknown" else {
            LoggingUtility.shared.log("Cannot check for app update: Missing bundle ID or initial version.")
            return
        }

        LoggingUtility.shared.log("Checking if app (\(bundleId)) was updated...")

        // Use `brew list --versions <bundleId>` to get the currently installed version
        // Example assumes bundleId is the correct formula/cask name for brew
        BrewBarUtility.shared.runBrewCommand(["list", "--versions", bundleId]) { [weak self] output, exitCode, error in
            guard let self else { return }

            guard exitCode == 0, let output, error == nil else {
                LoggingUtility.shared.log("Failed to get current version for \(bundleId) via brew. Error: \(error?.localizedDescription ?? "Exit code \(exitCode)"), Output: \(output ?? "N/A")")
                return
            }

            // Parse the output (e.g., "brewbar 1.2.3")
            let components = output.split(separator: " ", maxSplits: 1)
            if components.count == 2, let installedVersion = components.last?.trimmingCharacters(in: .whitespacesAndNewlines) {
                LoggingUtility.shared.log("Initial version: \(initialVersion), Currently installed version: \(installedVersion)")
                if installedVersion != initialVersion {
                    LoggingUtility.shared.log("App update detected! \(bundleId) changed from \(initialVersion) to \(installedVersion).")
                    DispatchQueue.main.async {
                        self.promptForRelaunch()
                    }
                } else {
                    LoggingUtility.shared.log("App (\(bundleId)) version (\(initialVersion)) hasn't changed.")
                }
            } else {
                LoggingUtility.shared.log("Could not parse version from brew output: \(output)")
            }
        }
    }

    private func promptForRelaunch() {
        let alert = NSAlert()
        alert.messageText = "Application Updated"
        alert.informativeText = "BrewBar was updated to a new version. Relaunch now to apply the changes?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Relaunch Now")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn { // Relaunch Now
            relaunchApp()
        }
    }

    private func relaunchApp() {
        LoggingUtility.shared.log("Relaunching application...")
        guard let appPath = Bundle.main.executablePath else {
            LoggingUtility.shared.log("Error: Could not get application path for relaunch.")
            return
        }

        // Use Process to launch 'open -a' after a short delay, then terminate self
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", appPath]

        // Optional: add a delay if needed, though 'open' might handle this gracefully
        // task.arguments = ["-g", "-a", appPath] // -g runs in background, might be smoother

        do {
            try task.run()
            LoggingUtility.shared.log("Relaunch command executed. Terminating current instance.")
            NSApp.terminate(nil)
        } catch {
            LoggingUtility.shared.log("Failed to relaunch application: \(error)")

            let alert = NSAlert()
            alert.messageText = "Failed to relaunch application"
            alert.informativeText = "Please relaunch the application manually."
            alert.alertStyle = .critical
            alert.runModal()
        }
    }

    // MARK: - Preferences & Other Actions

    @objc func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(appDelegate: self)
        }

        preferencesWindowController?.showWindow()
    }

    @objc func openLogsFolder() {
        LoggingUtility.shared.log("Opening log folder in Finder")
        NSWorkspace.shared.open(LoggingUtility.logDirectoryURL)
    }

    @objc func toggleNotifications(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "notificationsEnabled")
        LoggingUtility.shared.log("Notifications \(enabled ? "enabled" : "disabled")")
    }

    // MARK: - Wake from Sleep Notification

    @objc func handleWakeFromSleep() {
        LoggingUtility.shared.log("System woke from sleep")

        // Check if we have a next scheduled check time and it's in the past
        let now = Date()
        if let nextCheck = nextScheduledCheckTime, nextCheck < now {
            LoggingUtility.shared.log("Missed scheduled update during sleep, running now")
            checkForUpdates()
        } else {
            // Reschedule the timer to ensure it's accurate after sleep
            scheduleUpdateTimer()
        }
    }

    // Helper method to format dates for logging
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
