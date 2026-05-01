import AppKit
import Foundation
import UserNotifications

// MARK: - Shared preference key (nonisolated; string constant only)

enum BrewBarNotificationPreferences {
    /// UserDefaults key: in-app toggle for “show notifications when updates are available.”
    static let userToggleKey = "notificationsEnabled"
}

// MARK: - Notification Manager

/// Owns `UNUserNotificationCenter` setup, authorization, and local scheduling. All entry points are `@MainActor`.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Last known system authorization (refreshed when we read settings or complete a request).
    private(set) var notificationsAuthorized = false

    override private init() {
        super.init()
        if UserDefaults.standard.object(forKey: BrewBarNotificationPreferences.userToggleKey) == nil {
            UserDefaults.standard.set(true, forKey: BrewBarNotificationPreferences.userToggleKey)
        }
    }

    // MARK: - Lifecycle (call once from AppDelegate on the main thread)

    /// Registers the notification delegate and categories. Does **not** call `requestAuthorization` (must run in user or delivery context).
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let viewAction = UNNotificationAction(
            identifier: "VIEW_ACTION",
            title: "View Updates",
            options: .foreground
        )
        let updateCategory = UNNotificationCategory(
            identifier: "UPDATE_CATEGORY",
            actions: [viewAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([updateCategory])

        Task {
            await refreshAuthorizationFlagFromSystem()
            await logSettings(label: "after configure")
        }
    }

    /// BrewBar Settings toggle: missing key means enabled (matches Settings UI default).
    func isUserNotificationsToggleEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: BrewBarNotificationPreferences.userToggleKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: BrewBarNotificationPreferences.userToggleKey)
    }

    func setUserNotificationsToggleEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: BrewBarNotificationPreferences.userToggleKey)
    }

    // MARK: - Public API

    /// User tapped “Send Test Notification” — promote to a regular app first so TCC can attach permission to a foreground context.
    func sendTestNotification() async {
        guard isUserNotificationsToggleEnabled() else {
            LoggingUtility.shared.log("Test notification skipped: disabled in BrewBar Settings.")
            return
        }
        DockVisibility.promoteToRegularApp()
        await Task.yield()
        await logSettings(label: "before test")
        let authorized = await ensureAuthorized(for: .userFacingTest)
        guard authorized else {
            LoggingUtility.shared.log("Test notification skipped: not authorized.")
            return
        }
        await deliverLocalNotification(
            title: "BrewBar",
            subtitle: "Test notification",
            body: "If you see this banner or an entry in Notification Center, delivery is working.",
            categoryIdentifier: nil
        )
    }

    /// Called when AppState decides outdated packages warrant a notification.
    func scheduleUpdateAvailableNotice(outdatedCount: Int) async {
        guard isUserNotificationsToggleEnabled() else {
            LoggingUtility.shared.log("Update notification skipped: disabled in BrewBar Settings.")
            return
        }
        let authorized = await ensureAuthorized(for: .backgroundCheck)
        guard authorized else {
            LoggingUtility.shared.log("Update notification skipped: not authorized.")
            return
        }
        let suffix = outdatedCount == 1 ? "" : "s"
        await deliverLocalNotification(
            title: "Homebrew Updates Available",
            subtitle: "Click to view details",
            body: "\(outdatedCount) outdated package\(suffix) found.",
            categoryIdentifier: "UPDATE_CATEGORY"
        )
    }

    // MARK: - Authorization

    private enum AuthorizationRequestContext {
        case userFacingTest
        case backgroundCheck
    }

    private func refreshAuthorizationFlagFromSystem() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAuthorized = Self.allowsDelivery(settings)
    }

    private static func allowsDelivery(_ settings: UNNotificationSettings) -> Bool {
        switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                true
            case .denied, .notDetermined:
                false
            @unknown default:
                false
        }
    }

    /// Returns whether the app may schedule notifications (`authorized`, `provisional`, or `ephemeral`).
    private func ensureAuthorized(for context: AuthorizationRequestContext) async -> Bool {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()

        switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                notificationsAuthorized = true
                if settings.alertSetting == .disabled {
                    LoggingUtility.shared.log(
                        "Notification alertSetting is disabled; banners may not appear (Focus or per-app style)."
                    )
                }
                return true

            case .denied:
                notificationsAuthorized = false
                await logSettings(label: "authorization denied")
                LoggingUtility.shared.log(
                    "Notifications denied in System Settings (Notifications → BrewBar). Open System Settings to enable."
                )
                return false

            case .notDetermined:
                if context == .userFacingTest {
                    await Task.yield()
                }
                do {
                    let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge, .provisional])
                    if !granted {
                        LoggingUtility.shared.log("requestAuthorization returned false.")
                        await logSettings(label: "after requestAuthorization false")
                        return false
                    }
                } catch {
                    let ns = error as NSError
                    LoggingUtility.shared.log(
                        "requestAuthorization error: domain=\(ns.domain) code=\(ns.code) description=\(error.localizedDescription)"
                    )
                    if ns.domain == "UNErrorDomain", ns.code == 1 {
                        LoggingUtility.shared.log(
                            "UNError 1 usually means macOS refused notification registration for this process. Check that the app bundle is validly signed."
                        )
                    }
                    await logSettings(label: "after requestAuthorization error")
                    return false
                }
                settings = await center.notificationSettings()
                notificationsAuthorized = Self.allowsDelivery(settings)
                if !notificationsAuthorized {
                    await logSettings(label: "after request unexpected status")
                }
                return notificationsAuthorized

            @unknown default:
                notificationsAuthorized = false
                LoggingUtility.shared.log("Unknown authorizationStatus \(settings.authorizationStatus.rawValue).")
                return false
        }
    }

    // MARK: - Scheduling

    private func deliverLocalNotification(
        title: String,
        subtitle: String?,
        body: String,
        categoryIdentifier: String?
    ) async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        content.interruptionLevel = .active
        if let subtitle, !subtitle.isEmpty {
            content.subtitle = subtitle
        }
        if let categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        do {
            try await center.add(request)
            LoggingUtility.shared.log("Notification scheduled: \(title)")
        } catch {
            LoggingUtility.shared.log("center.add failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Diagnostics

    private func logSettings(label: String) async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        LoggingUtility.shared.log(
            "Notification settings [\(label)] authorizationStatus=\(s.authorizationStatus.rawValue) alertSetting=\(s.alertSetting.rawValue) soundSetting=\(s.soundSetting.rawValue) notificationCenterSetting=\(s.notificationCenterSetting.rawValue) badgeSetting=\(s.badgeSetting.rawValue)"
        )
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            LoggingUtility.shared.log("Presenting notification while app is active: \(notification.request.content.title)")
        }
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            AppState.shared.showOutdatedPackagesWindow()
        }
        completionHandler()
    }
}
