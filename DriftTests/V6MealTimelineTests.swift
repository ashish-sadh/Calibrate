import XCTest
@testable import Drift
import DriftCore

/// Tier-1 tests for `V6MealTimeline.payloads(from:now:)` — the pure factory
/// that maps today's `[FoodEntry]` into the fixed 4-slot Breakfast / Lunch /
/// Dinner / Snacks shape rendered by the Dashboard's V6 meals timeline.
///
/// Mirrors the discipline used in `V6BodyTileTests`: lock the formatter
/// behavior independently of the rendering layer so SwiftUI churn never
/// silently changes user-visible meal grouping.
@MainActor
final class V6MealTimelineTests: XCTestCase {

    // MARK: - Slot shape invariants

    func testPayloadsAlwaysReturnsExactlyFourSlotsInFixedOrder() {
        let slots = V6MealTimeline.payloads(from: [])
        XCTAssertEqual(slots.count, 4, "Timeline must always render 4 fixed slots")
        XCTAssertEqual(slots.map(\.mealType), [.breakfast, .lunch, .dinner, .snack],
                       "Slot order must be the V6 anatomy order, not whatever Dictionary returned")
    }

    func testEmptyEntriesPopulatesFourLogPromptSlots() {
        let slots = V6MealTimeline.payloads(from: [])
        for slot in slots {
            XCTAssertFalse(slot.isLogged, "\(slot.name) must be empty when no entries exist")
            XCTAssertEqual(slot.calories, 0)
            XCTAssertEqual(slot.itemSummary, "")
        }
    }

    func testEmptySlotsCarryDefaultReferenceTimes() {
        // Pin "now" to noon UTC so the reference-time formatter is locale-deterministic.
        let now = Date(timeIntervalSince1970: 1_762_956_000) // 2025-11-12T18:00:00Z
        let slots = V6MealTimeline.payloads(from: [], now: now)
        let byMeal = Dictionary(uniqueKeysWithValues: slots.map { ($0.mealType, $0) })
        XCTAssertTrue(byMeal[.breakfast]!.timeText.hasPrefix("~"),
                      "Empty breakfast slot shows the soft '~7:00 AM' affordance")
        XCTAssertTrue(byMeal[.lunch]!.timeText.hasPrefix("~"))
        XCTAssertTrue(byMeal[.dinner]!.timeText.hasPrefix("~"))
        XCTAssertEqual(byMeal[.snack]!.timeText, "Anytime",
                       "Snacks is anytime — never gets a default time tag")
    }

    // MARK: - Filled slot mapping

    func testFilledSlotSumsCaloriesAndKeepsItemSummary() {
        let entries = [
            makeEntry(name: "scrambled eggs", calories: 155, servings: 2, mealType: "breakfast"),
            makeEntry(name: "wheat toast", calories: 80, servings: 1, mealType: "breakfast"),
        ]
        let slots = V6MealTimeline.payloads(from: entries)
        let breakfast = slots.first { $0.mealType == .breakfast }!
        XCTAssertTrue(breakfast.isLogged)
        // 155 * 2 + 80 * 1 = 390
        XCTAssertEqual(breakfast.calories, 390)
        XCTAssertTrue(breakfast.itemSummary.contains("scrambled"))
        XCTAssertTrue(breakfast.itemSummary.contains("wheat toast"))
    }

    func testFilledSlotItemSummaryTruncatesItemsBeyondThree() {
        let entries = [
            makeEntry(name: "rice", calories: 200, mealType: "lunch", loggedOffsetSeconds: 0),
            makeEntry(name: "dal", calories: 100, mealType: "lunch", loggedOffsetSeconds: 10),
            makeEntry(name: "sabzi", calories: 80, mealType: "lunch", loggedOffsetSeconds: 20),
            makeEntry(name: "raita", calories: 60, mealType: "lunch", loggedOffsetSeconds: 30),
            makeEntry(name: "papad", calories: 30, mealType: "lunch", loggedOffsetSeconds: 40),
        ]
        let slots = V6MealTimeline.payloads(from: entries)
        let lunch = slots.first { $0.mealType == .lunch }!
        XCTAssertEqual(lunch.calories, 470)
        XCTAssertTrue(lunch.itemSummary.hasSuffix("+2"),
                      "5 items, first 3 by loggedAt asc, then '+2' tail; got '\(lunch.itemSummary)'")
        XCTAssertTrue(lunch.itemSummary.contains("rice"))
        XCTAssertTrue(lunch.itemSummary.contains("dal"))
        XCTAssertTrue(lunch.itemSummary.contains("sabzi"))
        XCTAssertFalse(lunch.itemSummary.contains("raita"),
                       "raita is item #4 — must be hidden under +2 tail")
    }

    func testFilledSlotItemSummaryClipsLongNamesToThreeWords() {
        let entries = [
            makeEntry(name: "homemade indian style chicken biryani extra spicy",
                      calories: 500, mealType: "dinner"),
        ]
        let slots = V6MealTimeline.payloads(from: entries)
        let dinner = slots.first { $0.mealType == .dinner }!
        XCTAssertEqual(dinner.itemSummary, "homemade indian style",
                       "First entry name keeps the first 3 words so the row stays a single line")
    }

    /// Missing `mealType` (legacy quick-add or AI flow that didn't tag) must
    /// land in the Snack slot, not silently drop. `MealType.snack` is the
    /// same fallback `MealType.resolve(...)` uses when no inheritance hint
    /// exists, so this keeps the surface consistent with the rest of the app.
    func testEntriesWithMissingMealTypeFallBackToSnack() {
        let entries = [
            makeEntry(name: "protein bar", calories: 200, mealType: nil),
        ]
        let slots = V6MealTimeline.payloads(from: entries)
        let snack = slots.first { $0.mealType == .snack }!
        XCTAssertTrue(snack.isLogged)
        XCTAssertEqual(snack.calories, 200)
        XCTAssertTrue(snack.itemSummary.contains("protein bar"))
    }

    func testEntriesWithUnknownMealTypeFallBackToSnack() {
        // A stray "brunch" or capitalized "BREAKFAST" should not just vanish —
        // a future AI tag mismatch can't silently strip calories from the row.
        let entries = [
            makeEntry(name: "mystery toast", calories: 90, mealType: "BREAKFAST"),
            makeEntry(name: "brunch bowl", calories: 350, mealType: "brunch"),
        ]
        let slots = V6MealTimeline.payloads(from: entries)
        let breakfast = slots.first { $0.mealType == .breakfast }!
        let snack = slots.first { $0.mealType == .snack }!
        XCTAssertTrue(breakfast.isLogged,
                      "Case-insensitive mealType match keeps 'BREAKFAST' in the breakfast slot")
        XCTAssertEqual(breakfast.calories, 90)
        XCTAssertEqual(snack.calories, 350,
                       "Unknown mealType ('brunch') routes to snack so no entry is dropped")
    }

    // MARK: - Identity stability

    /// Slot identity must be the meal type, not a per-invocation UUID — same
    /// rule the V6Ring / V6QuickLogRow chips follow. Without this, SwiftUI
    /// remounts every slot on each Dashboard recompute and the row "flickers"
    /// during the 3-min loadToday tick.
    func testSlotIdentityIsMealTypeNotUUID() {
        let slotsA = V6MealTimeline.payloads(from: [])
        let slotsB = V6MealTimeline.payloads(from: [])
        XCTAssertEqual(slotsA.map(\.id), ["breakfast", "lunch", "dinner", "snack"])
        XCTAssertEqual(slotsA.map(\.id), slotsB.map(\.id),
                       "Identity must be stable across calls or SwiftUI will remount on every recompute")
    }

    // MARK: - Construction smoke

    func testV6MealTimelineConstructsWithMixedFilledEmptySlots() {
        let entries = [
            makeEntry(name: "oatmeal", calories: 200, mealType: "breakfast"),
            makeEntry(name: "samosa", calories: 250, mealType: "snack"),
        ]
        let slots = V6MealTimeline.payloads(from: entries)
        let view = V6MealTimeline(slots: slots) { _ in }
        XCTAssertNotNil(view)
        XCTAssertEqual(slots.filter(\.isLogged).count, 2)
        XCTAssertEqual(slots.filter { !$0.isLogged }.count, 2)
    }

    // MARK: - Helpers

    private func makeEntry(
        name: String,
        calories: Double,
        servings: Double = 1,
        mealType: String?,
        loggedOffsetSeconds: Int = 0
    ) -> FoodEntry {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let when = Date().addingTimeInterval(TimeInterval(loggedOffsetSeconds))
        return FoodEntry(
            foodName: name,
            servingSizeG: 100,
            servings: servings,
            calories: calories,
            proteinG: 0,
            carbsG: 0,
            fatG: 0,
            fiberG: 0,
            loggedAt: iso.string(from: when),
            date: nil,
            mealType: mealType
        )
    }
}
