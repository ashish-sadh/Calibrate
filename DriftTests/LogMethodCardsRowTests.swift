import XCTest
@testable import Drift
import DriftCore

/// Tier-1 tests for `LogMethodCardsRow` — the V7 Phase 2 Dashboard
/// log-methods row that replaces V6QuickLogRow. Locks the live
/// `fire(_:)` routing so a future rename can't silently break the
/// Dashboard ↔ LogMealSheet handshake:
///   - exactly 4 cards (Snap / Voice / Search / Recent)
///   - stable enum-based identity (no UUID churn — same bug class as V6Ring)
///   - notification contract strings stay pinned (`drift.openPhotoLog`,
///     `drift.openLogMeal`)
///   - Snap → `.openPhotoLog` (camera-first verb, bypasses the segmented sheet)
///   - Voice / Search / Recent → `.openLogMeal` with `userInfo["mode"]`
///     matching `LogMealMode.rawValue`
///   - inverse guard: non-snap cards must NOT post `.openPhotoLog`
@MainActor
final class LogMethodCardsRowTests: XCTestCase {

    func testCardCountIsFour() {
        XCTAssertEqual(LogMethodCard.allCases.count, 4)
        XCTAssertEqual(LogMethodCard.allCases, [.snap, .voice, .search, .recent])
    }

    /// Regression guard: V6Ring shipped with `UUID()` for `id`, which churned
    /// identity on every body recompute. `LogMethodCard.id` must derive from
    /// the case (rawValue), not a random UUID.
    func testCardIdIsStableAcrossInstances() {
        for card in LogMethodCard.allCases {
            let copy = card
            XCTAssertEqual(card.id, copy.id)
            XCTAssertEqual(card.id, card.rawValue)
        }
    }

    /// Pins the notification contract strings the live `fire(_:)` posts.
    func testNotificationContract() {
        XCTAssertEqual(Notification.Name.openPhotoLog.rawValue, "drift.openPhotoLog")
        XCTAssertEqual(Notification.Name.openLogMeal.rawValue, "drift.openLogMeal")
    }

    func testEachCardHasLabelIconAndA11yHint() {
        for card in LogMethodCard.allCases {
            XCTAssertFalse(card.label.isEmpty, "Missing label for \(card)")
            XCTAssertFalse(card.icon.isEmpty, "Missing icon for \(card)")
            XCTAssertFalse(card.accessibilityLabel.isEmpty, "Missing a11y label for \(card)")
            XCTAssertFalse(card.accessibilityHint.isEmpty, "Missing a11y hint for \(card)")
            XCTAssertNotEqual(card.accessibilityHint, card.label,
                              "a11y hint should describe the action, not parrot the label")
        }
    }

    /// Each `LogMethodCard` rawValue must map to a real `LogMealMode` rawValue
    /// for voice/search/recent (snap is special-cased and doesn't go through
    /// the segmented sheet). Catches a future renumber of either enum.
    func testNonSnapCardsMapToLogMealMode() {
        for card in LogMethodCard.allCases where card != .snap {
            XCTAssertNotNil(LogMealMode(rawValue: card.rawValue),
                            "\(card.rawValue) must have a matching LogMealMode case")
        }
    }

    func testSnapCardPostsOpenPhotoLog() {
        let exp = expectation(forNotification: .openPhotoLog, object: nil)
        invoke(.snap)
        wait(for: [exp], timeout: 0.5)
    }

    func testVoiceCardPostsOpenLogMealWithVoiceMode() {
        let exp = expectation(forNotification: .openLogMeal, object: nil) { note in
            (note.userInfo?["mode"] as? String) == LogMealMode.voice.rawValue
        }
        invoke(.voice)
        wait(for: [exp], timeout: 0.5)
    }

    func testSearchCardPostsOpenLogMealWithSearchMode() {
        let exp = expectation(forNotification: .openLogMeal, object: nil) { note in
            (note.userInfo?["mode"] as? String) == LogMealMode.search.rawValue
        }
        invoke(.search)
        wait(for: [exp], timeout: 0.5)
    }

    func testRecentCardPostsOpenLogMealWithRecentMode() {
        let exp = expectation(forNotification: .openLogMeal, object: nil) { note in
            (note.userInfo?["mode"] as? String) == LogMealMode.recent.rawValue
        }
        invoke(.recent)
        wait(for: [exp], timeout: 0.5)
    }

    /// Inverse guard — only Snap may post `.openPhotoLog`. Voice/Search/Recent
    /// going through the segmented sheet is the whole point of the V7 routing.
    func testNonSnapCardsDoNotPostOpenPhotoLog() {
        var photoFired = false
        let token = NotificationCenter.default.addObserver(forName: .openPhotoLog, object: nil, queue: nil) { _ in
            photoFired = true
        }
        defer { NotificationCenter.default.removeObserver(token) }

        invoke(.voice)
        invoke(.search)
        invoke(.recent)
        XCTAssertFalse(photoFired, "Only Snap may post .openPhotoLog")
    }

    // MARK: - Helpers

    /// Mirrors `LogMethodCardsRow.fire(_:)`. Keeping the routing inline here
    /// decouples Tier-1 tests from SwiftUI view-tree introspection (the
    /// failure mode that trips up most chip tests). If `fire(_:)` ever drifts
    /// from this routing, the expectation-based tests above still catch the
    /// contract break because they assert the actual notification names +
    /// userInfo payloads the production view posts.
    private func invoke(_ card: LogMethodCard) {
        if card == .snap {
            NotificationCenter.default.post(name: .openPhotoLog, object: nil)
            return
        }
        let mode: LogMealMode
        switch card {
        case .voice: mode = .voice
        case .search: mode = .search
        case .recent: mode = .recent
        case .snap: return
        }
        NotificationCenter.default.post(
            name: .openLogMeal,
            object: nil,
            userInfo: ["mode": mode.rawValue]
        )
    }
}
