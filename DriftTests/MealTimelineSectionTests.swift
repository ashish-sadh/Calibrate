import XCTest
@testable import Drift
import DriftCore

/// Tier-1 tests for `MealTimelineSection.rows(from:)` — the pure factory
/// that maps today's `[FoodEntry]` into the dot-rail timeline rows rendered
/// on the V7 Today tab. Locks formatter behavior independently of the
/// rendering layer so a SwiftUI churn never silently changes meal display.
@MainActor
final class MealTimelineSectionTests: XCTestCase {

    // MARK: - Empty state

    func testEmptyEntriesYieldsNoRows() {
        let rows = MealTimelineSection.rows(from: [])
        XCTAssertTrue(rows.isEmpty, "No entries should produce no rows; the view renders the spec empty state")
    }

    func testEmptyStateViewConstructsWithEmptyEntries() {
        let view = MealTimelineSection(entries: [])
        XCTAssertNotNil(view, "View constructs cleanly with empty entries")
    }

    // MARK: - Row mapping

    func testSingleEntryProducesOneRowWithTotalCalories() {
        let entry = makeEntry(name: "scrambled eggs", calories: 155, servings: 2)
        let rows = MealTimelineSection.rows(from: [entry])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].foodName, "scrambled eggs")
        XCTAssertEqual(rows[0].kcal, 310, "kcal = calories * servings = 155 * 2 = 310")
    }

    func testEntryWithFractionalServingsRoundsToNearestKcal() {
        // 200 kcal * 1.5 servings = 300.0 → rounds to 300
        let entry = makeEntry(name: "dal", calories: 200, servings: 1.5)
        let rows = MealTimelineSection.rows(from: [entry])
        XCTAssertEqual(rows[0].kcal, 300)
    }

    func testMultipleEntriesAreSortedByLoggedAtAscending() {
        let eggs = makeEntry(name: "eggs", calories: 100, loggedOffsetSeconds: 60)
        let toast = makeEntry(name: "toast", calories: 80, loggedOffsetSeconds: 0)
        let coffee = makeEntry(name: "coffee", calories: 5, loggedOffsetSeconds: 30)
        let rows = MealTimelineSection.rows(from: [eggs, toast, coffee])
        XCTAssertEqual(rows.map(\.foodName), ["toast", "coffee", "eggs"],
                       "Rows are sorted ascending by loggedAt so the earliest meal sits at the top of the rail")
    }

    func testRowCarriesPerEntryMacros() {
        let entry = makeEntry(name: "paneer tikka", calories: 250, servings: 1,
                              proteinG: 18, carbsG: 6, fatG: 18, fiberG: 1)
        let rows = MealTimelineSection.rows(from: [entry])
        XCTAssertEqual(rows[0].proteinG, 18, accuracy: 0.001)
        XCTAssertEqual(rows[0].carbsG, 6, accuracy: 0.001)
        XCTAssertEqual(rows[0].fatG, 18, accuracy: 0.001)
        XCTAssertEqual(rows[0].fiberG, 1, accuracy: 0.001)
    }

    // MARK: - Identity stability

    /// Identity stability — DB-persisted entries use the row id, in-flight
    /// entries fall back to `foodName + timeText`. Without this, SwiftUI
    /// remounts every row on each 3-min Dashboard refresh tick.
    func testRowIdUsesEntryIdWhenAvailable() {
        let entry = makeEntry(id: 42, name: "rice", calories: 200)
        let rows = MealTimelineSection.rows(from: [entry])
        XCTAssertEqual(rows[0].id, "e42")
    }

    func testRowIdFallsBackToNameAndTimeForInFlightEntries() {
        let entry = makeEntry(id: nil, name: "rice", calories: 200)
        let rows = MealTimelineSection.rows(from: [entry])
        XCTAssertTrue(rows[0].id.hasPrefix("rice-"),
                      "Without an entry id, identity composes the name and the displayed time so SwiftUI keeps stable identity")
    }

    // MARK: - Time formatter robustness

    /// Entries with unparseable timestamps must not crash the row builder.
    /// Future AI pipeline could log a bad `loggedAt` and the dashboard would
    /// silently disappear if we propagated the error.
    func testEntryWithUnparseableLoggedAtRendersDashTime() {
        let entry = FoodEntry(
            foodName: "mystery meal",
            servingSizeG: 100,
            servings: 1,
            calories: 100,
            proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0,
            loggedAt: "not-a-date",
            date: nil,
            mealType: nil
        )
        let rows = MealTimelineSection.rows(from: [entry])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].timeText, "—",
                       "Unparseable timestamp renders an em-dash, not a crash")
    }

    // MARK: - View construction smoke

    func testMealTimelineSectionConstructsWithMixedEntries() {
        let entries = [
            makeEntry(name: "oats", calories: 200),
            makeEntry(name: "samosa", calories: 250),
        ]
        let view = MealTimelineSection(entries: entries)
        XCTAssertNotNil(view, "View constructs for the populated case")
    }

    // MARK: - Helpers

    private func makeEntry(
        id: Int64? = nil,
        name: String,
        calories: Double,
        servings: Double = 1,
        proteinG: Double = 0,
        carbsG: Double = 0,
        fatG: Double = 0,
        fiberG: Double = 0,
        loggedOffsetSeconds: Int = 0
    ) -> FoodEntry {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let when = Date().addingTimeInterval(TimeInterval(loggedOffsetSeconds))
        return FoodEntry(
            id: id,
            foodName: name,
            servingSizeG: 100,
            servings: servings,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            fiberG: fiberG,
            loggedAt: iso.string(from: when),
            date: nil,
            mealType: nil
        )
    }
}
