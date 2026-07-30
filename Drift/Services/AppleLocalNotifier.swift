import UserNotifications
import DriftCore

/// iOS side of the `LocalNotifier` seam (#1162) — social alerts (a client
/// trained, a coaching message, a connection request) raised through
/// `UNUserNotificationCenter`.
///
/// Separate from `NotificationService`, which owns SCHEDULED health nudges
/// (protein, supplements, meal and medication reminders). Those are calendar
/// triggers the app plans in advance; these are immediate alerts about
/// something that already happened on someone else's phone. Sharing one type
/// would mean one authorization story and one identifier space for two
/// unrelated jobs.
struct AppleLocalNotifier: LocalNotifier {

    /// Distinct category so social alerts can carry their own actions later
    /// without disturbing the health-nudge category.
    private static let categoryID = "drift_social_alert"

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    func notify(id: String, title: String, body: String, deepLink: String?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        if let deepLink { content.userInfo = ["deepLink": deepLink] }
        // nil trigger = deliver now. The id de-duplicates: re-adding the same
        // identifier replaces rather than stacks, so a poll that runs twice
        // over the same unread message notifies once.
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
