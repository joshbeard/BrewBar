import AppKit
import Observation
import SwiftUI

struct IntervalOption: Identifiable {
    let name: String
    let value: TimeInterval
    var id: String {
        name
    }
}

enum SheetAction: Equatable {
    case check
    case update
    case upgradeAll
}

private enum AppStatePersistentKeys {
    /// Sorted `name|availableVersion` lines — any change means “new” updates vs last successful check.
    static let outdatedFingerprint = "brewBarOutdatedFingerprint"
    /// Legacy key from count-only notification logic (removed); used once to avoid a duplicate notify on upgrade.
    static let legacyLastOutdatedCount = "brewBarLastOutdatedCount"
}

@Observable
class AppState {
    static let shared = AppState()

    // MARK: - State

    var currentOutdatedPackages: [PackageInfo] = []
    var currentInstalledPackages: [InstalledPackageInfo] = []
    var lastCheckTime: Date?
    var nextScheduledCheckTime: Date?
    var lastCheckError: Bool = false
    var isChecking: Bool = false
    var pendingSheetAction: SheetAction?

    /// Shown from the menu bar when BrewBar itself was upgraded via Homebrew.
    var showRelaunchPrompt = false
    /// Shown in `OutdatedPackagesView` when the user closes the window while a brew task runs.
    var showClosePackagesWhileBrewRunningAlert = false

    var outdatedPackagesWindowController: NSWindowController?
    /// Inline SwiftTerm in the packages window; used for close-confirmation while a task runs.
    var isPackagesWindowBrewTaskRunning: Bool = false

    @ObservationIgnored private var updateTimer: Timer?
    @ObservationIgnored private var initialAppVersion: String?
    @ObservationIgnored private var appBundleIdentifier: String?

    let intervalDefaultsKey = "updateCheckInterval"
    let customIntervalsKey = "customIntervals"
    let loginItemEnabledKey = "loginItemEnabled"
    let defaultInterval: TimeInterval = 86400

    // MARK: - Computed Properties (Menu)

    var menuBarIcon: String {
        if isChecking { return "arrow.clockwise" }
        if lastCheckError { return "xmark.circle" }
        if currentOutdatedPackages.isEmpty {
            return lastCheckTime != nil ? "checkmark.circle" : "mug"
        }
        return "mug.fill"
    }

    var statusText: String {
        if isChecking { return "Checking for updates..." }
        if lastCheckError { return "Error checking updates" }
        if currentOutdatedPackages.isEmpty { return "Homebrew is up to date" }
        let count = currentOutdatedPackages.count
        let maxDisplay = 3
        var text = "\(count) outdated package\(count == 1 ? "" : "s")"
        let names = currentOutdatedPackages.prefix(maxDisplay).map { $0.name }.joined(separator: ", ")
        text += ": \(names)"
        if count > maxDisplay {
            text += " (+\(count - maxDisplay) more)"
        }
        return text
    }

    var lastCheckedText: String {
        guard let lastCheckTime else { return "Last checked: Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "Last checked: \(formatter.string(from: lastCheckTime))"
    }

    var nextCheckText: String {
        guard let nextCheckTime = nextScheduledCheckTime else { return "Next check: Manual only" }
        let interval = nextCheckTime.timeIntervalSinceNow

        if interval <= 5 { return "Next check: Checking soon..." }

        let timeUntil = formatTimeInterval(interval)
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let timeString = timeFormatter.string(from: nextCheckTime)
        let calendar = Calendar.current

        let dateString: String
        if calendar.isDateInToday(nextCheckTime) {
            dateString = "Today at \(timeString)"
        } else if calendar.isDateInTomorrow(nextCheckTime) {
            dateString = "Tomorrow at \(timeString)"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d 'at' h:mm a"
            dateString = dateFormatter.string(from: nextCheckTime)
        }

        return "Next check: \(dateString) (\(timeUntil))"
    }

    var isViewPackagesEnabled: Bool {
        lastCheckTime != nil
    }

    var intervalOptions: [String: TimeInterval] {
        var options: [String: TimeInterval] = [
            "Every Hour": 60 * 60,
            "Every 6 Hours": 6 * 60 * 60,
            "Every Day": 24 * 60 * 60,
            "Every 3 Days": 3 * 24 * 60 * 60,
            "Every Week": 7 * 24 * 60 * 60,
            "Manually": 0,
        ]

        if let customIntervals = UserDefaults.standard.dictionary(forKey: customIntervalsKey) as? [String: TimeInterval] {
            for (name, interval) in customIntervals where !options.keys.contains(name) {
                options[name] = interval
            }
        }

        return options
    }

    var sortedIntervalOptions: [IntervalOption] {
        intervalOptions.map { IntervalOption(name: $0.key, value: $0.value) }
            .sorted { $0.value < $1.value }
    }

    var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    // MARK: - Lifecycle

    func startup() {
        initialAppVersion = appVersionString
        appBundleIdentifier = "brewbar"

        Task {
            await checkForUpdates(displayOutput: false)
            await refreshInstalledPackages()
            scheduleUpdateTimer()
        }

        LoggingUtility.shared.performLogMaintenance()

        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        LoggingUtility.shared.log("BrewBar v\(appVersionString) (\(buildNumber)) starting up")
        LoggingUtility.shared.log("System: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        LoggingUtility.shared.log("Brew path: \(BrewBarUtility.shared.brewPath ?? "Not found")")

        configureLoginItem()
    }

    func cleanup() {
        updateTimer?.invalidate()
        updateTimer = nil
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Timer Scheduling

    func scheduleUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
        let interval = getCurrentInterval()

        guard interval > 0 else {
            nextScheduledCheckTime = nil
            LoggingUtility.shared.log("Update checks set to manual.")
            return
        }

        // Anchor the next fire to lastCheckTime so sleep/wake cycles and incidental
        // reschedules don't push the check endlessly forward.
        let anchor = lastCheckTime ?? Date()
        var nextFire = anchor.addingTimeInterval(interval)

        // If the computed time is already in the past (or imminent), fire shortly.
        let minDelay: TimeInterval = 5
        if nextFire.timeIntervalSinceNow < minDelay {
            nextFire = Date().addingTimeInterval(minDelay)
        }

        nextScheduledCheckTime = nextFire
        let delay = nextFire.timeIntervalSinceNow

        // One-shot timer; after firing we reschedule based on the new lastCheckTime.
        // Use `.common` so checks still run during event-tracking (menu open, resize, etc.).
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            LoggingUtility.shared.performLogMaintenance()
            Task { @MainActor in
                await self.checkForUpdates(runUpdate: true)
                self.scheduleUpdateTimer()
            }
        }
        timer.tolerance = min(60, delay * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer

        LoggingUtility.shared.log(
            "Next update check in \(Int(delay))s at \(formatDate(nextFire)) (anchored to \(lastCheckTime.map(formatDate) ?? "now"))")
    }

    func getCurrentInterval() -> TimeInterval {
        if UserDefaults.standard.object(forKey: intervalDefaultsKey) == nil {
            UserDefaults.standard.set(defaultInterval, forKey: intervalDefaultsKey)
            return defaultInterval
        }

        let savedInterval = UserDefaults.standard.double(forKey: intervalDefaultsKey)
        if intervalOptions.values.contains(savedInterval) {
            return savedInterval
        } else {
            UserDefaults.standard.set(defaultInterval, forKey: intervalDefaultsKey)
            return defaultInterval
        }
    }

    func setInterval(_ interval: TimeInterval) {
        UserDefaults.standard.set(interval, forKey: intervalDefaultsKey)
        scheduleUpdateTimer()
    }

    // MARK: - Login Item

    func configureLoginItem() {
        let enabled = UserDefaults.standard.object(forKey: loginItemEnabledKey) != nil
            ? UserDefaults.standard.bool(forKey: loginItemEnabledKey)
            : true
        LoginItemUtility.setLoginItemEnabled(enabled)
    }

    func isLoginItemEnabled() -> Bool {
        LoginItemUtility.isLoginItemEnabled()
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: loginItemEnabledKey)
        LoginItemUtility.setLoginItemEnabled(enabled)
    }

    // MARK: - Background Check Logic

    func checkForUpdates(displayOutput: Bool = false, runUpdate: Bool = false) async {
        if displayOutput {
            LoggingUtility.shared.log("Warning: checkForUpdates(displayOutput: true) called directly.")
            return
        }

        guard !BrewBarManager.shared.isCheckInProgress else {
            LoggingUtility.shared.log("Background check already in progress. Skipping.")
            return
        }

        BrewBarManager.shared.isCheckInProgress = true
        defer { BrewBarManager.shared.isCheckInProgress = false }

        lastCheckError = false
        isChecking = true
        LoggingUtility.shared.log("Starting background check...")

        if runUpdate {
            let updateCommand = BrewBarManager.shared.updateCommand
            LoggingUtility.shared.log("Running brew update: \(updateCommand.joined(separator: " "))")

            do {
                let (_, exitCode) = try await BrewBarUtility.shared.runBrewCommand(updateCommand)
                if exitCode != 0 {
                    LoggingUtility.shared.log("Brew update failed with exit code: \(exitCode)")
                } else {
                    LoggingUtility.shared.log("Brew update completed successfully")
                }
            } catch {
                LoggingUtility.shared.log("Brew update failed with error: \(error.localizedDescription)")
            }
        }

        await checkForOutdatedPackages()
        isChecking = false
    }

    private func checkForOutdatedPackages() async {
        do {
            let (output, exitCode) = try await BrewBarUtility.shared.runBrewCommand(["outdated", "--verbose"])

            lastCheckTime = Date()

            if exitCode == 0 {
                let packages = BrewBarManager.shared.parsePackagesWithVersions(from: output)
                LoggingUtility.shared.log("Background check found \(packages.count) outdated packages")
                let currentCount = packages.count

                let fingerprint: String
                if packages.isEmpty {
                    fingerprint = ""
                } else {
                    fingerprint = packages
                        .map { "\($0.name)|\($0.availableVersion)" }
                        .sorted()
                        .joined(separator: "\n")
                }
                let fpKey = AppStatePersistentKeys.outdatedFingerprint
                let hasStoredFingerprint = UserDefaults.standard.object(forKey: fpKey) != nil
                let previousFingerprint = UserDefaults.standard.string(forKey: fpKey) ?? ""

                // Notify whenever the outdated set/versions change — not only when the count changes
                // (e.g. one update replaces another with the same list length).
                let shouldNotify: Bool
                if !hasStoredFingerprint {
                    shouldNotify = currentCount > 0
                    if UserDefaults.standard.object(forKey: AppStatePersistentKeys.legacyLastOutdatedCount) != nil {
                        UserDefaults.standard.removeObject(forKey: AppStatePersistentKeys.legacyLastOutdatedCount)
                    }
                } else {
                    shouldNotify = currentCount > 0 && fingerprint != previousFingerprint
                }

                if shouldNotify {
                    let reason = hasStoredFingerprint ? "fingerprint changed" : "first check with outdated packages"
                    LoggingUtility.shared.log(
                        "Scheduling update notification (\(reason), \(currentCount) package(s))."
                    )
                    await NotificationManager.shared.scheduleUpdateAvailableNotice(outdatedCount: currentCount)
                }
                UserDefaults.standard.set(fingerprint, forKey: fpKey)
                lastCheckError = false

                let enrichedPackages = await BrewBarManager.shared.enrichOutdatedPackagesWithSource(packages: packages)
                currentOutdatedPackages = enrichedPackages
            } else {
                LoggingUtility.shared.log("Error in background check (status \(exitCode)): \(output)")
                currentOutdatedPackages = []
                lastCheckError = true
            }
        } catch {
            lastCheckTime = Date()
            LoggingUtility.shared.log("Error checking for outdated packages: \(error.localizedDescription)")
            lastCheckError = true
            currentOutdatedPackages = []
        }
    }

    func refreshInstalledPackages() async {
        LoggingUtility.shared.log("Fetching installed packages")
        let packages = await BrewBarManager.shared.fetchInstalledPackages()
        currentInstalledPackages = packages
        LoggingUtility.shared.log("Found \(packages.count) installed packages")
    }

    // MARK: - Window Management

    func showOutdatedPackagesWindow() {
        if let existingController = outdatedPackagesWindowController,
           let window = existingController.window
        {
            DockVisibility.promoteToRegularApp(keyWindow: window)
            return
        }

        LoggingUtility.shared.log("Creating packages window...")

        let hostingController = NSHostingController(
            rootView: OutdatedPackagesView(appState: self)
        )
        hostingController.sizingOptions = [.minSize, .intrinsicContentSize]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        // Match SwiftUI root min size so resize limits apply on first layout, not only after expanding.
        window.minSize = NSSize(width: 600, height: 520)
        window.center()
        window.setFrameAutosaveName("OutdatedPackagesWindow")
        window.contentViewController = hostingController
        window.title = "Homebrew Packages"
        window.isReleasedWhenClosed = false
        window.delegate = NSApp.delegate as? NSWindowDelegate

        outdatedPackagesWindowController = NSWindowController(window: window)
        outdatedPackagesWindowController?.showWindow(nil)
        DockVisibility.promoteToRegularApp(keyWindow: window)
    }

    // MARK: - Menu Actions

    func triggerUpdate() {
        LoggingUtility.shared.log("Update DB triggered from menu.")
        showOutdatedPackagesWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.pendingSheetAction = .update
        }
    }

    func triggerUpgradeAll() {
        LoggingUtility.shared.log("Upgrade All triggered from menu.")
        showOutdatedPackagesWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.pendingSheetAction = .upgradeAll
        }
    }

    // MARK: - Task Completion

    func handleTaskCompletion(commandArgs: [String], exitCode: Int32?) {
        guard let exitCode else {
            LoggingUtility.shared.log("Task completed with no exit code. Triggering full refresh.")
            Task { await triggerFullBackgroundRefresh() }
            return
        }

        if exitCode == 0 {
            LoggingUtility.shared.log("Task \(commandArgs.joined(separator: " ")) completed successfully.")
            var wasUpgradeAll = false

            if commandArgs.first == "upgrade" && commandArgs.count > 1 {
                let upgradedPackages = commandArgs.dropFirst()
                currentOutdatedPackages.removeAll { upgradedPackages.contains($0.name) }
                LoggingUtility.shared.log("Optimistic update: Removed \(upgradedPackages.joined(separator: ", ")) from outdated list.")
                if let bundleId = appBundleIdentifier, upgradedPackages.contains(bundleId) {
                    Task { await checkIfAppWasUpdated() }
                }
            } else if commandArgs.first == "uninstall" && commandArgs.count > 1 {
                let names = BrewBarUtility.packageNames(fromUninstallArguments: commandArgs)
                for packageName in names {
                    currentInstalledPackages.removeAll { $0.name == packageName }
                    currentOutdatedPackages.removeAll { $0.name == packageName }
                }
                if !names.isEmpty {
                    LoggingUtility.shared.log(
                        "Optimistic update: Removed \(names.joined(separator: ", ")) from installed/outdated lists.")
                }
            } else if commandArgs.first == "update" || (commandArgs.first == "upgrade" && commandArgs.count == 1) {
                LoggingUtility.shared.log("'\(commandArgs.first ?? "")' command finished. Triggering full background refresh.")
                if commandArgs.first == "upgrade" { wasUpgradeAll = true }
                Task { await triggerFullBackgroundRefresh() }
            }

            if wasUpgradeAll { Task { await checkIfAppWasUpdated() } }
        } else {
            LoggingUtility.shared.log("Task \(commandArgs.joined(separator: " ")) failed with exit code \(exitCode). Triggering full refresh.")
            Task { await triggerFullBackgroundRefresh() }
        }

        Task {
            try? await Task.sleep(for: .seconds(1))
            await self.checkForUpdates(displayOutput: false)
            await self.refreshInstalledPackages()
            self.scheduleUpdateTimer()
        }
    }

    private func triggerFullBackgroundRefresh() async {
        await checkForUpdates(displayOutput: false)
        await refreshInstalledPackages()
    }

    // MARK: - App Update Check

    private func checkIfAppWasUpdated() async {
        guard let bundleId = appBundleIdentifier, let initialVersion = initialAppVersion, initialVersion != "Unknown" else {
            LoggingUtility.shared.log("Cannot check for app update: Missing bundle ID or initial version.")
            return
        }

        LoggingUtility.shared.log("Checking if app (\(bundleId)) was updated...")

        do {
            let (output, exitCode) = try await BrewBarUtility.shared.runBrewCommand(["list", "--versions", bundleId])
            guard exitCode == 0 else {
                LoggingUtility.shared.log("Failed to get current version for \(bundleId). Exit code \(exitCode)")
                return
            }

            let components = output.split(separator: " ", maxSplits: 1)
            if components.count == 2, let installedVersion = components.last?.trimmingCharacters(in: .whitespacesAndNewlines) {
                LoggingUtility.shared.log("Initial version: \(initialVersion), Currently installed: \(installedVersion)")
                if installedVersion != initialVersion {
                    LoggingUtility.shared.log("App update detected! \(bundleId) changed from \(initialVersion) to \(installedVersion).")
                    await MainActor.run { showRelaunchPrompt = true }
                }
            }
        } catch {
            LoggingUtility.shared.log("Failed to check app version: \(error.localizedDescription)")
        }
    }

    func performRelaunchFromPrompt() {
        showRelaunchPrompt = false
        relaunchApp()
    }

    func requestPackagesWindowCloseConfirmation() {
        showClosePackagesWhileBrewRunningAlert = true
    }

    func confirmPackagesWindowCloseWhileTaskRunning() {
        showClosePackagesWhileBrewRunningAlert = false
        isPackagesWindowBrewTaskRunning = false
        outdatedPackagesWindowController?.close()
    }

    func cancelPackagesWindowCloseConfirmation() {
        showClosePackagesWhileBrewRunningAlert = false
    }

    private func relaunchApp() {
        LoggingUtility.shared.log("Relaunching application...")
        guard let appPath = Bundle.main.executablePath else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", appPath]

        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            LoggingUtility.shared.log("Failed to relaunch: \(error)")
        }
    }

    // MARK: - Wake from Sleep

    func handleWakeFromSleep() {
        LoggingUtility.shared.log("System woke from sleep")
        // scheduleUpdateTimer() anchors to lastCheckTime, so if the interval has
        // elapsed during sleep, the timer fires in ~5 seconds. No special-case logic needed.
        scheduleUpdateTimer()
    }

    // MARK: - Helpers

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        if interval <= 0 { return "now" }
        if interval < 60 { return "< 1m" }

        let minutes = Int(interval / 60) % 60
        let hours = Int(interval / 3600)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
