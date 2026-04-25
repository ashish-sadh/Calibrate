import UserNotifications
import DriftCore

/// Schedules local push notifications for health nudges (protein, supplements, workouts).
/// All logic is on-device — no cloud, no tracking. Reuses BehaviorInsightService detection.
@MainActor
enum NotificationService {

    private static let categoryID = "drift_health_nudge"

    /// Call on app launch and after relevant data changes.
    /// Checks conditions, requests permission if needed, schedules/cancels notifications.
    static func refreshScheduledAlerts() async {
        let center = UNUserNotificationCenter.current()

        guard Preferences.healthNudgesEnabled else {
            // Disabled — just clear any previously scheduled notifications
            center.removeAllPendingNotificationRequests()
            return
        }

        // Remove all pending — we reschedule fresh
        center.removeAllPendingNotificationRequests()

        // Check if there are any alerts worth sending
        let alerts = BehaviorInsightService.computeProactiveAlerts()
        guard !alerts.isEmpty else { return }

        // Request permission if not yet determined (only when we have something to send)
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard let granted = try? await center.requestAuthorization(options: [.alert, .sound]),
                  granted else { return }
        case .denied:
            return // User said no — respect it
        case .authorized, .provisional, .ephemeral:
            break // Good to go
        @unknown default:
            break
        }

        // Combine alerts into one notification (don't spam)
        let (title, body) = composeNotification(from: alerts)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryID

        // Schedule for 6pm today (or tomorrow if past 6pm)
        let trigger = nextEveningTrigger()

        let request = UNNotificationRequest(
            identifier: "drift_daily_nudge",
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    // MARK: - Composition (internal for testability)

    /// Compose a single notification from multiple alerts.
    static func composeNotification(from alerts: [BehaviorInsight]) -> (title: String, body: String) {
        if alerts.count == 1 {
            return (alerts[0].title, alerts[0].detail)
        }

        // Multiple alerts — summarize
        let titles = alerts.map(\.title)
        let title = "Health check-in"
        let body = titles.joined(separator: " · ")
        return (title, body)
    }

    /// Returns a calendar trigger for 6pm today if before 6pm, otherwise 6pm tomorrow.
    static func nextEveningTrigger() -> UNCalendarNotificationTrigger {
        var components = DateComponents()
        components.hour = 18
        components.minute = 0
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
}
