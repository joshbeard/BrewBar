import Foundation
import UserNotifications

// MARK: - Notification Manager
class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    // UserDefaults key for notification preference
    let notificationsEnabledKey = "notificationsEnabled"

    // Whether system notifications are authorized
    var notificationsAuthorized = true

    override init() {
        super.init()

        // Always ensure notifications are enabled by default
        if UserDefaults.standard.object(forKey: notificationsEnabledKey) == nil {
            UserDefaults.standard.set(true, forKey: notificationsEnabledKey)
        }

        setupNotifications()
    }

    func setupNotifications() {
        // Set up notification delegate
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Register notification category for update notifications
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

        // Register category
        center.setNotificationCategories([updateCategory])

        // Request permission to show notifications
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                LoggingUtility.shared.log("Notification permission granted.")
                self.notificationsAuthorized = true
            } else {
                LoggingUtility.shared.log("Notification permission denied or restricted.")
                self.notificationsAuthorized = false
            }
        }

        // Check current authorization status
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsAuthorized = (settings.authorizationStatus == .authorized)
            }
        }
    }

    func notificationsEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: notificationsEnabledKey)
    }

    func toggleNotifications(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: notificationsEnabledKey)
    }

    func sendNotification(count: Int) {
        guard notificationsEnabled() && notificationsAuthorized else { return }

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Homebrew Updates Available"
        content.body = "\(count) outdated package\(count == 1 ? "" : "s") found."
        content.sound = UNNotificationSound.default

        // Add the category to make it appear as an alert if user has alerts enabled
        content.categoryIdentifier = "UPDATE_CATEGORY"
        content.subtitle = "Click to view details"

        // Create a unique identifier for this notification
        let identifier = "com.homebrewmenubar.updates-\(Date().timeIntervalSince1970)"

        // Use a slight delay to increase chance it shows as an alert
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        // Create the request
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        // Add the request to the notification center
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                LoggingUtility.shared.log("Error sending notification: \(error.localizedDescription)")
                self.notificationsAuthorized = false // Disable future attempts if this fails
            } else {
                LoggingUtility.shared.log("Outdated packages notification sent successfully")
            }
        }
    }

    // UNUserNotificationCenterDelegate method
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        // When user clicks on the notification, show the outdated packages window
        NotificationCenter.default.post(name: NSNotification.Name("ShowOutdatedPackagesWindow"), object: nil)
        completionHandler()
    }
}
