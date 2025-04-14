import Cocoa
import SwiftUI
import UserNotifications
import ServiceManagement

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    // Managers
    var menuBarManager: MenuBarManager!
    private var terminalWindowController: TerminalWindowController?
    private var preferencesWindowController: PreferencesWindowController?

    // Timer for checking updates
    private var updateTimer: Timer?

    // State tracking
    var isUpdateRunning = false
    var currentOutdatedPackages: [PackageInfo] = []
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

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Hide dock icon and prevent app from showing in the dock or app switcher
        NSApp.setActivationPolicy(.accessory)

        // Initialize crash reporter
        CrashReporter.shared.setup()

        // Start with logging app version and environment
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        LoggingUtility.shared.log("BrewBar v\(appVersion) (\(buildNumber)) starting up")
        LoggingUtility.shared.log("System: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        LoggingUtility.shared.log("Brew path: \(BrewBarUtility.shared.brewPath ?? "Not found")")

        // Configure login item based on preferences
        configureLoginItem()

        // Initialize managers
        menuBarManager = MenuBarManager(appDelegate: self)
        menuBarManager.setup()
        terminalWindowController = TerminalWindowController()

        // Setup notification observer for notification clicks
        NotificationCenter.default.addObserver(self,
                                             selector: #selector(showOutdatedPackagesWindow),
                                             name: NSNotification.Name("ShowOutdatedPackagesWindow"),
                                             object: nil)

        // Setup wake from sleep notification
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // Setup timer based on saved preference
        scheduleUpdateTimer()

        // Perform initial check
        checkForUpdates()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Clean up: terminate any running check process and timers
        BrewBarManager.shared.updateCheckTask?.interrupt()
        updateTimer?.invalidate()
        menuBarManager.cleanup()

        // Remove observers
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Timer Scheduling

    func scheduleUpdateTimer() {
        updateTimer?.invalidate() // Invalidate existing timer first
        updateTimer = nil

        let interval = getCurrentInterval()

        // Only schedule if interval > 0 (not manual)
        if interval > 0 {
            updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.checkForUpdates()
            }

            // Calculate and store the next check time
            let nextCheck = Date().addingTimeInterval(interval)
            nextScheduledCheckTime = nextCheck

            LoggingUtility.shared.log("Scheduled update check every \(interval) seconds. Next check at \(formatDate(nextCheck))")

            // Update the menu to show the next check time
            menuBarManager.updateNextCheckMenuItem()
        } else {
            nextScheduledCheckTime = nil
            LoggingUtility.shared.log("Update checks set to manual.")
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
            return
        }

        LoggingUtility.shared.log("Creating packages window with fetch for installed packages")

        // Create a shared view state
        let viewState = PackageViewState()

        // Create a temporary view with empty installed packages
        let initialView = OutdatedPackagesView(
            packages: currentOutdatedPackages,
            installed: [],
            errorOccurred: lastCheckError,
            viewState: viewState,
            updateSinglePackage: { [weak self] packageName in
                self?.upgradeSinglePackage(packageName)
            },
            updateSelectedPackages: { [weak self] packageNames in
                self?.upgradeSelectedPackages(packageNames)
            },
            updateAllPackages: { [weak self] in
                self?.upgradeAllPackages()
            },
            uninstallPackage: { [weak self] packageName in
                self?.uninstallPackage(packageName)
            },
            uninstallSelectedPackages: { [weak self] packageNames in
                self?.uninstallSelectedPackages(packageNames)
            },
            checkNow: { [weak self, weak viewState] in
                // Set window to checking state first
                viewState?.isCheckingForUpdates = true
                LoggingUtility.shared.log("DEBUG: Window CheckNow: Set viewState.isCheckingForUpdates = true")

                // Run the check for updates, refresh window on completion
                LoggingUtility.shared.log("DEBUG: Window CheckNow: Starting checkForUpdates()")
                self?.checkForUpdates(displayOutput: true) { // Pass true for displayOutput
                    // This block executes *after* checkForUpdates is complete
                    LoggingUtility.shared.log("DEBUG: Window CheckNow: checkForUpdates completed, calling refreshPackagesWindow()")
                    // Use weak self here as well
                    self?.refreshPackagesWindow(viewState: viewState)
                }
                LoggingUtility.shared.log("DEBUG: Window CheckNow: checkForUpdates() initiated with completion handler")
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

        // Fetch installed packages and update the view
        BrewBarManager.shared.fetchInstalledPackages { [weak self, weak viewState] packages in
            guard let self = self,
                  let window = self.outdatedPackagesWindowController?.window,
                  let contentVC = window.contentViewController as? NSHostingController<OutdatedPackagesView> else {
                return
            }

            LoggingUtility.shared.log("Updating window with \(packages.count) installed packages")

            // Create updated view with installed packages
            let updatedView = OutdatedPackagesView(
                packages: self.currentOutdatedPackages,
                installed: packages,
                errorOccurred: self.lastCheckError,
                viewState: viewState ?? PackageViewState(),
                updateSinglePackage: { [weak self] packageName in
                    self?.upgradeSinglePackage(packageName)
                },
                updateSelectedPackages: { [weak self] packageNames in
                    self?.upgradeSelectedPackages(packageNames)
                },
                updateAllPackages: { [weak self] in
                    self?.upgradeAllPackages()
                },
                uninstallPackage: { [weak self] packageName in
                    self?.uninstallPackage(packageName)
                },
                uninstallSelectedPackages: { [weak self] packageNames in
                    self?.uninstallSelectedPackages(packageNames)
                },
                checkNow: { [weak self, weak viewState] in
                    // Set window to checking state first
                    viewState?.isCheckingForUpdates = true
                    LoggingUtility.shared.log("DEBUG: Window CheckNow (nested): Set viewState.isCheckingForUpdates = true")

                    // Run the check for updates, refresh window on completion
                    LoggingUtility.shared.log("DEBUG: Window CheckNow (nested): Starting checkForUpdates()")
                    self?.checkForUpdates(displayOutput: true) { // Pass true for displayOutput
                        // This block executes *after* checkForUpdates is complete
                        LoggingUtility.shared.log("DEBUG: Window CheckNow (nested): checkForUpdates completed, calling refreshPackagesWindow()")
                        // Use weak self here as well
                        self?.refreshPackagesWindow(viewState: viewState)
                    }
                    LoggingUtility.shared.log("DEBUG: Window CheckNow (nested): checkForUpdates() initiated with completion handler")
                }
            )

            // Update the UI
            contentVC.rootView = updatedView
        }
    }

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        // Check if the closing window is our outdated packages window
        if (notification.object as? NSWindow) == outdatedPackagesWindowController?.window {
            LoggingUtility.shared.log("Outdated packages window closed.")
            outdatedPackagesWindowController = nil // Release the controller reference
        }
    }

    // MARK: - Update Operations

    @objc func checkForUpdatesManual() {
        // Rate limiting - prevent refreshing more than once a minute
        if let lastCheck = lastCheckTime, Date().timeIntervalSince(lastCheck) < 60 {
            // Show a notification that we're rate limiting
            LoggingUtility.shared.log("Rate limiting: Preventing check more than once per minute")

            let alert = NSAlert()
            alert.messageText = "Please Wait"
            alert.informativeText = "You can only check for updates once per minute."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        LoggingUtility.shared.log("Manual update check triggered.")
        checkForUpdates(displayOutput: true)
    }

    func checkForUpdates(displayOutput: Bool = false, completion: (() -> Void)? = nil) {
        // If an update check is already running, cancel it before starting a new one.
        BrewBarManager.shared.updateCheckTask?.interrupt()
        BrewBarManager.shared.updateCheckTask = nil

        // Reset error state to start fresh
        lastCheckError = false

        // Update menu to show checking state
        menuBarManager.updateMenu(outdatedPackages: [], checking: true)

        // Disable show outdated button while checking
        if let showOutdatedItem = menuBarManager.menu?.item(withTitle: "Show Outdated Packages...") {
             showOutdatedItem.isEnabled = false
        }

        // Log check starting
        LoggingUtility.shared.log("Starting check for updates")

        // Use the found brew path
        guard let brewExecutable = BrewBarUtility.shared.brewPath else {
            LoggingUtility.shared.log("ERROR: Brew executable not found")
            DispatchQueue.main.async {
                self.lastCheckTime = Date()
                self.menuBarManager.updateCheckNowMenuItemTitle()
                self.updateMenuWithError()

                if let showOutdatedItem = self.menuBarManager.menu?.item(withTitle: "Show Outdated Packages...") {
                    showOutdatedItem.isEnabled = true
                }
            }
            return
        }

        LoggingUtility.shared.log("Using brew at path: \(brewExecutable)")

        // Show terminal window if requested
        if displayOutput {
            terminalWindowController?.showWindow()
            terminalWindowController?.appendOutput("Checking for outdated packages...\n", color: NSColor.systemBlue)
        }

        // Create a Process to run brew outdated directly
        let task = Process()
        task.executableURL = URL(fileURLWithPath: brewExecutable)
        task.arguments = ["outdated", "--verbose"] // Only use --verbose to get version information

        // Setup environment variables
        var environment = ProcessInfo.processInfo.environment
        let brewBinPath = URL(fileURLWithPath: brewExecutable).deletingLastPathComponent().path

        // Make sure PATH includes Homebrew's bin directory
        let paths = [
            brewBinPath,              // Homebrew's bin directory
            "/usr/bin",               // System binaries
            "/bin",                   // Basic Unix binaries
            "/usr/sbin",              // System admin binaries
            "/sbin",                  // System admin binaries
            "/usr/local/bin"          // Common local binaries
        ]

        let pathValue = paths.joined(separator: ":")
        environment["PATH"] = pathValue
        task.environment = environment

        LoggingUtility.shared.log("Using PATH: \(pathValue)")

        // Setup pipes for output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        // Store reference to allow cancellation
        BrewBarManager.shared.updateCheckTask = task

        // If showing terminal window, show the command being run
        if displayOutput {
            terminalWindowController?.appendOutput("Running: brew outdated --verbose\n\n", color: NSColor.systemGreen)

            // Handle output in real-time for the terminal window
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
                guard let self = self else { return }

                let data = fileHandle.availableData
                if data.count > 0, let output = String(data: data, encoding: .utf8) {
                    self.terminalWindowController?.appendOutput(output)
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
                guard let self = self else { return }

                let data = fileHandle.availableData
                if data.count > 0, let output = String(data: data, encoding: .utf8) {
                    self.terminalWindowController?.appendOutput(output, color: NSColor.systemRed)
                }
            }
        }

        do {
            try task.run()

            LoggingUtility.shared.log("Successfully started brew outdated process")

            // Async handler for when process completes
            task.terminationHandler = { [weak self] process in
                guard let self = self else { return }

                // Read output if we're not showing it in a terminal window
                var output = ""
                var errorOutput = ""

                if !displayOutput {
                    // Read output from pipes if we're not streaming it to the terminal
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                    output = String(data: outputData, encoding: .utf8) ?? ""
                    errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                } else {
                    // Clean up the readability handlers
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                }

                DispatchQueue.main.async {
                    BrewBarManager.shared.updateCheckTask = nil
                    self.lastCheckTime = Date()
                    self.menuBarManager.updateCheckNowMenuItemTitle()

                    // Recalculate the next check time
                    let interval = self.getCurrentInterval()
                    if interval > 0 {
                        self.nextScheduledCheckTime = Date().addingTimeInterval(interval)
                        self.menuBarManager.updateNextCheckMenuItem()
                    }

                    var packages: [PackageInfo] = []
                    var encounteredError = false

                    if process.terminationStatus == 0 {
                        // Success - parse packages
                        if displayOutput {
                            // Get the output from the terminal window's text
                            if let text = self.terminalWindowController?.textView?.string {
                                // Parse packages from the terminal text
                                packages = BrewBarManager.shared.parsePackagesWithVersions(from: text)
                            }
                        } else {
                            // Parse packages from the captured output
                            packages = BrewBarManager.shared.parsePackagesWithVersions(from: output)
                        }

                        LoggingUtility.shared.log("Found \(packages.count) outdated packages")

                        if displayOutput {
                            // Show summary in the terminal window
                            if packages.isEmpty {
                                self.terminalWindowController?.appendOutput("\nNo outdated packages found.\n", color: NSColor.systemGreen)
                            } else {
                                self.terminalWindowController?.appendOutput("\nFound \(packages.count) outdated package(s).\n", color: NSColor.systemOrange)
                            }
                        }

                        // Send notification if outdated packages changed from 0
                        let currentCount = packages.count
                        if currentCount > 0 && self.lastOutdatedCount == 0 {
                            NotificationManager.shared.sendNotification(count: currentCount)
                        }
                        self.lastOutdatedCount = currentCount
                    } else {
                        // Error during brew command
                        let logMessage = "Error checking for updates (status \(process.terminationStatus)): \(errorOutput.isEmpty ? output : errorOutput)"
                        LoggingUtility.shared.log(logMessage)
                        encounteredError = true

                        if displayOutput {
                            self.terminalWindowController?.appendOutput("\nError checking for updates: \(process.terminationStatus)\n", color: NSColor.systemRed)
                        }
                    }

                    // Enrich packages with source information before updating UI
                    BrewBarManager.shared.enrichOutdatedPackagesWithSource(packages: packages) { [weak self] enrichedPackages in
                        guard let self = self else { return }

                        // Update state with enriched packages
                        self.currentOutdatedPackages = enrichedPackages
                        self.menuBarManager.updateMenu(outdatedPackages: enrichedPackages, errorOccurred: encounteredError)

                        // Update terminal window if displayed
                        if displayOutput {
                            self.terminalWindowController?.appendOutput("\nCheck completed at \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))\n", color: NSColor.systemBlue)
                        }

                        // Call the completion handler if provided (AFTER enrichment)
                        completion?()
                    }
                }
            }
        } catch {
            LoggingUtility.shared.log("ERROR executing brew outdated: \(error.localizedDescription)")

            if displayOutput {
                terminalWindowController?.appendOutput("ERROR: Failed to execute brew outdated: \(error.localizedDescription)\n", color: NSColor.systemRed)
            }

            DispatchQueue.main.async {
                BrewBarManager.shared.updateCheckTask = nil
                self.lastCheckTime = Date()
                self.menuBarManager.updateCheckNowMenuItemTitle()
                self.updateMenuWithError()

                if let showOutdatedItem = self.menuBarManager.menu?.item(withTitle: "Show Outdated Packages...") {
                    showOutdatedItem.isEnabled = true
                }

                // Call completion handler even on error
                completion?()
            }
        }
    }

    func updateMenuWithError() {
        lastCheckError = true
        menuBarManager.updateMenu(errorOccurred: true)
    }

    func updateMenuWithUpdateStatus() {
        menuBarManager.updateInProgressMenuItem?.isHidden = !isUpdateRunning
    }

    // MARK: - Package Operations

    // Run homebrew operations
    @objc func runUpdate() {
        runBrewCommand(BrewBarManager.shared.updateCommand, title: "Updating Homebrew")
    }

    @objc func runUpgradeAll() {
        runBrewCommand(BrewBarManager.shared.upgradeCommand, title: "Upgrading All Packages")
    }

    func upgradeSinglePackage(_ packageName: String) {
        runBrewCommand(["upgrade", packageName], title: "Upgrading \(packageName)")
    }

    func upgradeSelectedPackages(_ packageNames: [String]) {
        var args = ["upgrade"]
        args.append(contentsOf: packageNames)
        runBrewCommand(args, title: "Upgrading Selected Packages")
    }

    func upgradeAllPackages() {
        runUpgradeAll()
    }

    func uninstallPackage(_ packageName: String) {
        // Check if it's a cask
        let isCask = currentOutdatedPackages.contains { $0.name == packageName && $0.source == "cask" }

        var args = ["uninstall"]
        if isCask {
            args.append("--cask")
        }
        args.append(packageName)

        runBrewCommand(args, title: "Uninstalling \(packageName)")
    }

    func uninstallSelectedPackages(_ packageNames: [String]) {
        let alert = NSAlert()
        alert.messageText = "Uninstall Packages"
        alert.informativeText = "Are you sure you want to uninstall \(packageNames.count) selected packages?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            // User confirmed uninstall
            for packageName in packageNames {
                uninstallPackage(packageName)
            }
        }
    }

    private func runBrewCommand(_ args: [String], title: String) {
        guard let brewExecutable = BrewBarUtility.shared.brewPath else {
            LoggingUtility.shared.log("ERROR: Brew executable not found")
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = "Homebrew executable not found."
            alert.alertStyle = .critical
            alert.runModal()
            return
        }

        // Prevent multiple operations at once
        if isUpdateRunning {
            let alert = NSAlert()
            alert.messageText = "Operation in Progress"
            alert.informativeText = "Please wait for the current operation to complete."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        // Show terminal window
        terminalWindowController?.showWindow()
        terminalWindowController?.appendOutput("\(title)...\n", color: NSColor.systemBlue)
        terminalWindowController?.appendOutput("Running: brew \(args.joined(separator: " "))\n\n", color: NSColor.systemGreen)

        // Update menu
        isUpdateRunning = true
        updateMenuWithUpdateStatus()

        // Create process
        let task = Process()
        task.executableURL = URL(fileURLWithPath: brewExecutable)
        task.arguments = args

        // Setup pipes
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        // Store for cancellation
        BrewBarManager.shared.updateProcess = task

        // Stream output to terminal
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            guard let self = self else { return }

            let data = fileHandle.availableData
            if data.count > 0, let output = String(data: data, encoding: .utf8) {
                self.terminalWindowController?.appendOutput(output)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            guard let self = self else { return }

            let data = fileHandle.availableData
            if data.count > 0, let output = String(data: data, encoding: .utf8) {
                self.terminalWindowController?.appendOutput(output, color: NSColor.systemRed)
            }
        }

        do {
            try task.run()

            // Completion handler
            task.terminationHandler = { [weak self] process in
                guard let self = self else { return }

                // Clean up handlers
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                DispatchQueue.main.async {
                    // Update status
                    self.isUpdateRunning = false
                    self.updateMenuWithUpdateStatus()
                    BrewBarManager.shared.updateProcess = nil

                    // Show completion message
                    if process.terminationStatus == 0 {
                        self.terminalWindowController?.appendOutput("\n\(title) completed successfully.\n", color: NSColor.systemGreen)

                        // If this was an upgrade operation, refresh the outdated packages window
                        let wasUpgradeOperation = args.contains("upgrade")
                        if wasUpgradeOperation {
                            // First refresh the outdated packages list
                            self.checkForUpdates(displayOutput: false)

                            // Then update the packages window if it's open
                            if let windowController = self.outdatedPackagesWindowController,
                               let window = windowController.window,
                               let contentVC = window.contentViewController as? NSHostingController<OutdatedPackagesView> {

                                // Create updated view with current data
                                let updatedView = OutdatedPackagesView(
                                    packages: self.currentOutdatedPackages,
                                    installed: contentVC.rootView.installedPackages,
                                    errorOccurred: self.lastCheckError,
                                    viewState: contentVC.rootView.viewState,
                                    updateSinglePackage: contentVC.rootView.updateSinglePackage,
                                    updateSelectedPackages: contentVC.rootView.updateSelectedPackages,
                                    updateAllPackages: contentVC.rootView.updateAllPackages,
                                    uninstallPackage: contentVC.rootView.uninstallPackage,
                                    uninstallSelectedPackages: contentVC.rootView.uninstallSelectedPackages,
                                    checkNow: contentVC.rootView.checkNow
                                )

                                // Update the content view
                                contentVC.rootView = updatedView
                            }
                        }
                    } else {
                        self.terminalWindowController?.appendOutput("\n\(title) failed with error code \(process.terminationStatus).\n", color: NSColor.systemRed)
                    }

                    // Check for updates again to refresh the menu
                    self.checkForUpdates()
                }
            }
        } catch {
            LoggingUtility.shared.log("ERROR running brew command: \(error.localizedDescription)")
            terminalWindowController?.appendOutput("ERROR: Failed to execute brew command: \(error.localizedDescription)\n", color: NSColor.systemRed)

            // Reset state
            isUpdateRunning = false
            updateMenuWithUpdateStatus()
            BrewBarManager.shared.updateProcess = nil
        }
    }

    // MARK: - Preferences

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

    // MARK: - Notification Preferences

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

    // Helper to refresh the packages window with the latest data
    private func refreshPackagesWindow(viewState: PackageViewState?) {
        LoggingUtility.shared.log("DEBUG: refreshPackagesWindow called")

        // Safety check for window controller and content view
        guard let windowController = outdatedPackagesWindowController,
              let window = windowController.window,
              let contentVC = window.contentViewController as? NSHostingController<OutdatedPackagesView> else {
            LoggingUtility.shared.log("DEBUG: Window controller or content view not available")

            // Always reset the spinner if viewState was provided, even if window is gone
            DispatchQueue.main.async {
                viewState?.isCheckingForUpdates = false
                LoggingUtility.shared.log("DEBUG: Reset spinner state even though window was gone")
            }

            return
        }

        LoggingUtility.shared.log("DEBUG: Got window controller and content view")

        // Always make sure to turn off the checking state
        DispatchQueue.main.async {
            if let viewState = viewState {
                LoggingUtility.shared.log("DEBUG: Immediately turning off checking state")
                viewState.isCheckingForUpdates = false
            }
        }

        // Fetch installed packages and update the view
        LoggingUtility.shared.log("DEBUG: Starting fetchInstalledPackages")
        BrewBarManager.shared.fetchInstalledPackages { [weak self] packages in
            guard let self = self else {
                LoggingUtility.shared.log("DEBUG: self was nil in completion handler")
                // In case there's a viewState, make sure to turn off spinner
                DispatchQueue.main.async {
                    viewState?.isCheckingForUpdates = false
                }
                return
            }

            LoggingUtility.shared.log("DEBUG: 🔄 fetchInstalledPackages completed with \(packages.count) packages")

            // Create updated view with latest data, reusing the current view state
            let updatedView = OutdatedPackagesView(
                packages: self.currentOutdatedPackages,
                installed: packages,
                errorOccurred: self.lastCheckError,
                viewState: contentVC.rootView.viewState,  // Reuse the existing view state
                updateSinglePackage: contentVC.rootView.updateSinglePackage,
                updateSelectedPackages: contentVC.rootView.updateSelectedPackages,
                updateAllPackages: contentVC.rootView.updateAllPackages,
                uninstallPackage: contentVC.rootView.uninstallPackage,
                uninstallSelectedPackages: contentVC.rootView.uninstallSelectedPackages,
                checkNow: contentVC.rootView.checkNow
            )

            // Update the UI on the main thread
            DispatchQueue.main.async {
                LoggingUtility.shared.log("DEBUG: 🏁 Updating view with latest data")
                // Update the UI
                contentVC.rootView = updatedView

                // Also force viewState to be off, for good measure
                contentVC.rootView.viewState.isCheckingForUpdates = false
                LoggingUtility.shared.log("DEBUG: View updated and viewState.isCheckingForUpdates set to false")
            }
        }
    }
}