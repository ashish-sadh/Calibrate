import XCTest
import UserNotifications
@testable import Drift

@MainActor
final class NotificationServiceTests: XCTestCase {

    // MARK: - Preference Defaults

    func testHealthNudgesDefaultsToOff() {
        UserDefaults.standard.removeObject(forKey: "drift_health_nudges")
        XCTAssertFalse(Preferences.healthNudgesEnabled, "Health nudges should default to OFF")
    }

    func testOnlineFoodSearchDefaultsToOn() {
        UserDefaults.standard.removeObject(forKey: "drift_online_food_search")
        XCTAssertTrue(Preferences.onlineFoodSearchEnabled, "Online food search should default to ON")
    }

    // MARK: - Toggles

    func testHealthNudgesToggle() {
        let original = UserDefaults.standard.object(forKey: "drift_health_nudges")
        defer { if let o = original { UserDefaults.standard.set(o, forKey: "drift_health_nudges") } else { UserDefaults.standard.removeObject(forKey: "drift_health_nudges") } }

        Preferences.healthNudgesEnabled = true
        XCTAssertTrue(Preferences.healthNudgesEnabled)
        Preferences.healthNudgesEnabled = false
        XCTAssertFalse(Preferences.healthNudgesEnabled)
    }

    func testOnlineFoodSearchToggle() {
        let original = UserDefaults.standard.object(forKey: "drift_online_food_search")
        defer { if let o = original { UserDefaults.standard.set(o, forKey: "drift_online_food_search") } else { UserDefaults.standard.removeObject(forKey: "drift_online_food_search") } }

        Preferences.onlineFoodSearchEnabled = false
        XCTAssertFalse(Preferences.onlineFoodSearchEnabled)
        Preferences.onlineFoodSearchEnabled = true
        XCTAssertTrue(Preferences.onlineFoodSearchEnabled)
    }

    // MARK: - Notification Composition

    func testComposeNotificationSingleAlert() {
        let alert = BehaviorInsight(icon: "heart.fill", title: "Protein below target", detail: "3 days under 150g protein.", isPositive: false)
        let (title, body) = NotificationService.composeNotification(from: [alert])
        XCTAssertEqual(title, "Protein below target")
        XCTAssertEqual(body, "3 days under 150g protein.")
    }

    func testComposeNotificationMultipleAlerts_UsesHealthCheckinTitle() {
        let a1 = BehaviorInsight(icon: "heart", title: "Alert One", detail: "Detail one", isPositive: false)
        let a2 = BehaviorInsight(icon: "pill", title: "Alert Two", detail: "Detail two", isPositive: false)
        let (title, _) = NotificationService.composeNotification(from: [a1, a2])
        XCTAssertEqual(title, "Health check-in")
    }

    func testComposeNotificationMultipleAlerts_BodyContainsAllTitles() {
        let a1 = BehaviorInsight(icon: "heart", title: "Alert One", detail: "Detail one", isPositive: false)
        let a2 = BehaviorInsight(icon: "pill", title: "Alert Two", detail: "Detail two", isPositive: false)
        let a3 = BehaviorInsight(icon: "figure", title: "Alert Three", detail: "Detail three", isPositive: false)
        let (_, body) = NotificationService.composeNotification(from: [a1, a2, a3])
        XCTAssertTrue(body.contains("Alert One"))
        XCTAssertTrue(body.contains("Alert Two"))
        XCTAssertTrue(body.contains("Alert Three"))
    }

    func testComposeNotificationMultipleAlerts_DotSeparated() {
        let a1 = BehaviorInsight(icon: "a", title: "First", detail: "d1", isPositive: false)
        let a2 = BehaviorInsight(icon: "b", title: "Second", detail: "d2", isPositive: true)
        let (_, body) = NotificationService.composeNotification(from: [a1, a2])
        XCTAssertTrue(body.contains(" · "), "Multiple alert titles should be dot-separated")
    }

    func testNextEveningTriggerSchedulesAt6PM() {
        let trigger = NotificationService.nextEveningTrigger()
        XCTAssertEqual(trigger.dateComponents.hour, 18)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
        XCTAssertFalse(trigger.repeats, "Daily nudge should not auto-repeat")
    }

    // MARK: - BehaviorInsight Struct

    func testBehaviorInsightPositiveFlag() {
        let insight = BehaviorInsight(icon: "figure.run", title: "Workouts help", detail: "Active weeks trending better.", isPositive: true)
        XCTAssertTrue(insight.isPositive)
        XCTAssertEqual(insight.icon, "figure.run")
        XCTAssertEqual(insight.title, "Workouts help")
        XCTAssertEqual(insight.detail, "Active weeks trending better.")
    }

    func testBehaviorInsightNegativeFlag() {
        let insight = BehaviorInsight(icon: "exclamationmark.triangle", title: "Protein gap", detail: "Below 80% adherence.", isPositive: false)
        XCTAssertFalse(insight.isPositive)
    }

    // MARK: - Sleep Insight Edge Cases (via computeInsights)

    func testSleepInsightRequiresMin7Entries() {
        let sixEntries = (0..<6).map { i -> (date: Date, hours: Double) in
            (date: Calendar.current.date(byAdding: .day, value: -i, to: Date())!, hours: i % 2 == 0 ? 8.0 : 5.0)
        }
        let insights = BehaviorInsightService.computeInsights(sleepHistory: sixEntries)
        let hasSleepInsight = insights.contains { $0.icon == "moon.zzz.fill" }
        XCTAssertFalse(hasSleepInsight, "< 7 sleep entries should produce no sleep insight")
    }

    func testSleepInsightEmptyHistoryProducesNoInsight() {
        let insights = BehaviorInsightService.computeInsights(sleepHistory: [])
        let hasSleepInsight = insights.contains { $0.icon == "moon.zzz.fill" }
        XCTAssertFalse(hasSleepInsight, "Empty sleep history should produce no sleep insight")
    }

    func testSleepInsightWith7EntriesButNoCalorieDataProducesNoInsight() {
        // 7 entries with good/poor mix — but DB has no calorie data for these dates
        // so goodSleepCals and poorSleepCals stay empty → guard fails → no insight
        let entries = (0..<7).map { i -> (date: Date, hours: Double) in
            (date: Calendar.current.date(byAdding: .day, value: -i - 100, to: Date())!, hours: i % 2 == 0 ? 8.0 : 5.0)
        }
        let insights = BehaviorInsightService.computeInsights(sleepHistory: entries)
        let hasSleepInsight = insights.contains { $0.icon == "moon.zzz.fill" }
        XCTAssertFalse(hasSleepInsight, "No calorie data should produce no sleep insight even with sufficient sleep entries")
    }

    func testSleepInsightExactly7EntriesAllGoodSleep() {
        // All good sleep (7h+) → poorSleepCals will be empty → guard fails
        let entries = (0..<7).map { i -> (date: Date, hours: Double) in
            (date: Calendar.current.date(byAdding: .day, value: -i - 200, to: Date())!, hours: 8.0)
        }
        let insights = BehaviorInsightService.computeInsights(sleepHistory: entries)
        let hasSleepInsight = insights.contains { $0.icon == "moon.zzz.fill" }
        XCTAssertFalse(hasSleepInsight, "All-good-sleep entries should produce no sleep insight without poor sleep days")
    }

    // MARK: - Service API Smoke Tests

    @MainActor
    func testComputeInsightsReturnsValidArray() {
        let insights = BehaviorInsightService.computeInsights()
        XCTAssertNotNil(insights, "computeInsights() should return a valid array")
        for insight in insights {
            XCTAssertFalse(insight.title.isEmpty, "Every insight should have a non-empty title")
            XCTAssertFalse(insight.detail.isEmpty, "Every insight should have a non-empty detail")
            XCTAssertFalse(insight.icon.isEmpty, "Every insight should have a non-empty icon")
        }
    }

    @MainActor
    func testComputeProactiveAlertsReturnsValidArray() {
        let alerts = BehaviorInsightService.computeProactiveAlerts()
        XCTAssertNotNil(alerts)
        for alert in alerts {
            XCTAssertFalse(alert.title.isEmpty, "Every alert should have a non-empty title")
            XCTAssertFalse(alert.icon.isEmpty, "Every alert should have a non-empty icon")
        }
    }
}
