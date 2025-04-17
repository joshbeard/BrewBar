import Cocoa
import SwiftUI
import UserNotifications
import ServiceManagement
import SwiftTerm

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

    // UserDefaults keys
    let intervalDefaultsKey = "updateCheckInterval"
    let customIntervalsKey = "customIntervals"
    let loginItemEnabledKey = "loginItemEnabled"

    let defaultInterval: TimeInterval = 86400 // 1 day

    // Default intervals (in seconds)
    var intervalOptions: [String: TimeInterval] {
        get {
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

        // Start initial data load
        checkForUpdates(displayOutput: false) { [weak self] in
            guard let self = self else { return }
            self.refreshInstalledPackages() {
                self.scheduleUpdateTimer()
                // Final UI update after all initial loading
                self.menuBarManager.updateMenu(outdatedPackages: self.currentOutdatedPackages,
                                               checking: false,
                                               errorOccurred: self.lastCheckError)
            }
        }

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
            updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.checkForUpdates()
            }
            let nextCheck = Date().addingTimeInterval(interval)
            nextScheduledCheckTime = nextCheck
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
              let interval = selectedItem.representedObject as? TimeInterval else {
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
             guard let self = self else { return }
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
            NotificationCenter.default.post(name: Self.runCheckInSheetNotification, object: nil)
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
    func checkForUpdates(displayOutput: Bool = false, completion: (() -> Void)? = nil) {
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
        // ... (disable menu item) ...
        LoggingUtility.shared.log("Starting background check...")

        guard BrewBarUtility.shared.brewPath != nil else {
            LoggingUtility.shared.log("ERROR: Brew executable not found")
            DispatchQueue.main.async {
                self.lastCheckTime = Date()
                self.menuBarManager.updateCheckNowMenuItemTitle()
                self.updateMenuWithError()

                if let showOutdatedItem = self.menuBarManager.menu?.item(withTitle: "View Packages...") {
                    showOutdatedItem.isEnabled = true // Re-enable on error
                }
                completion?() // Call completion even on error
            }
            return
        }

        // Safely unwrap here since we guarded against nil above
        let brewExecutable = BrewBarUtility.shared.brewPath!

        let task = Process()
        task.executableURL = URL(fileURLWithPath: brewExecutable)
        task.arguments = ["outdated", "--verbose"]

        // Setup pipes for output and error
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        // Set environment variables to prevent interactive prompts from Homebrew
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_INSTALL_UPGRADE"] = "1"
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        environment["HOMEBREW_NO_EMOJI"] = "1"
        task.environment = environment

        BrewBarManager.shared.updateCheckTask = task

        do {
            // Construct command string safely for logging
            let commandString = "brew \((task.arguments ?? []).joined(separator: " "))"
            try task.run()
            // Log *after* successful start, using the commandString variable
            LoggingUtility.shared.log("Started background command: \(commandString)")

            task.terminationHandler = { [weak self] process in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                guard let self = self else {
                    DispatchQueue.main.async { completion?() }
                    return
                }

                DispatchQueue.main.async {
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                    BrewBarManager.shared.updateCheckTask = nil
                    self.lastCheckTime = Date()
                    self.menuBarManager.updateCheckNowMenuItemTitle()
                    // ... (recalculate next check time and update specific menu item) ...

                    let packages: [PackageInfo]
                    let encounteredError: Bool

                    if process.terminationStatus == 0 {
                        packages = BrewBarManager.shared.parsePackagesWithVersions(from: output)
                        LoggingUtility.shared.log("Background check found \(packages.count) outdated packages")
                        let currentCount = packages.count
                        if currentCount > 0 && self.lastOutdatedCount == 0 { NotificationManager.shared.sendNotification(count: currentCount) }
                        self.lastOutdatedCount = currentCount
                        self.lastCheckError = false
                        encounteredError = false // Assign within the if block
                    } else {
                        let logMessage = "Error in background check (status \(process.terminationStatus)): \(errorOutput.isEmpty ? output : errorOutput)"
                        LoggingUtility.shared.log(logMessage)
                        packages = [] // Assign empty array on error
                        encounteredError = true // Assign within the else block
                        self.lastCheckError = true
                    }

                    BrewBarManager.shared.enrichOutdatedPackagesWithSource(packages: packages) { [weak self] enrichedPackages in
                        guard let self = self else {
                             DispatchQueue.main.async { completion?() }
                            return
                        }
                        self.currentOutdatedPackages = enrichedPackages
                        // Final menu update after enrichment
                        self.menuBarManager.updateMenu(outdatedPackages: enrichedPackages, checking: false, errorOccurred: encounteredError)
                        // ... (re-enable menu item) ...
                        completion?() // Call completion *after* all processing
                    }
                }
            }
        } catch {
            // ... (error handling for task.run) ...
            DispatchQueue.main.async { completion?() }
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
            guard let self = self else { return }
            self.currentInstalledPackages = packages
            LoggingUtility.shared.log("Found \(packages.count) installed packages")
            completion?()
        }
    }

    // Refreshes the content of the packages window if it's open.
    private func refreshPackagesWindow(viewState: PackageViewState? = nil) {
        guard let windowController = outdatedPackagesWindowController,
              let window = windowController.window,
              let contentVC = window.contentViewController as? NSHostingController<OutdatedPackagesView> else {
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
        guard let exitCode = exitCode else {
            LoggingUtility.shared.log("Task completed with no exit code (terminated via signal?). Triggering full refresh.")
            triggerFullBackgroundRefresh()
            return
        }

        if exitCode == 0 {
            LoggingUtility.shared.log("Task \(commandArgs.joined(separator: " ")) completed successfully.")
            var needsOptimisticRefresh = false

            // Check for specific command types eligible for optimistic update
            if commandArgs.first == "upgrade" && commandArgs.count > 1 {
                // Specific package upgrade: remove from outdated list
                let upgradedPackages = commandArgs.dropFirst()
                currentOutdatedPackages.removeAll { upgradedPackages.contains($0.name) }
                LoggingUtility.shared.log("Optimistic update: Removed \(upgradedPackages.joined(separator: ", ")) from outdated list.")
                needsOptimisticRefresh = true

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
                triggerFullBackgroundRefresh()
                needsOptimisticRefresh = false // Don't do optimistic refresh for these
            }

            // Perform optimistic refresh if flag is set
            if needsOptimisticRefresh {
                 DispatchQueue.main.async {
                     self.refreshPackagesWindow()
                 }
            }

        } else {
            // Command failed
            LoggingUtility.shared.log("Task \(commandArgs.joined(separator: " ")) failed with exit code \(exitCode). Triggering full refresh.")
            // Trigger full refresh on failure to ensure UI consistency
             triggerFullBackgroundRefresh()
        }
    }

    // Triggers a full background data refresh.
    private func triggerFullBackgroundRefresh() {
        self.checkForUpdates(displayOutput: false) { [weak self] in
            self?.refreshInstalledPackages()
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