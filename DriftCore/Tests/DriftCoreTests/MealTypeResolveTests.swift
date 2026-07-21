import Foundation
@testable import DriftCore
import Testing

/// Tier-0 coverage for recent-entry inheritance in `MealType.resolve`.
struct MealTypeResolveTests {
    private func localDate(hour: Int, minute: Int = 0) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 21,
            hour: hour,
            minute: minute
        )))
    }

    private func entry(mealType: String?, at date: Date, useSQLiteTimestamp: Bool = false) -> FoodEntry {
        let loggedAt: String
        if useSQLiteTimestamp {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            loggedAt = formatter.string(from: date)
        } else {
            loggedAt = ISO8601DateFormatter().string(from: date)
        }

        return FoodEntry(
            foodName: "Test food",
            servingSizeG: 100,
            calories: 100,
            loggedAt: loggedAt,
            mealType: mealType
        )
    }

    @Test func inheritsMostRecentMealRegardlessOfInputOrder() throws {
        let now = try localDate(hour: 14)
        let olderBreakfast = entry(mealType: "breakfast", at: now.addingTimeInterval(-2 * 3600))
        let newerDinner = entry(mealType: "dinner", at: now.addingTimeInterval(-30 * 60))

        #expect(MealType.resolve(now: now, recentEntries: [olderBreakfast, newerDinner]) == .dinner)
    }

    @Test func inheritWindowExcludesExactUpperBoundary() throws {
        let now = try localDate(hour: 12)
        let justInside = entry(mealType: "breakfast", at: now.addingTimeInterval(-(3 * 3600) + 1))
        let atBoundary = entry(mealType: "breakfast", at: now.addingTimeInterval(-3 * 3600))

        #expect(MealType.resolve(now: now, recentEntries: [justInside]) == .breakfast)
        #expect(MealType.resolve(now: now, recentEntries: [atBoundary]) == .lunch)
    }

    @Test func recentSnackFallsBackToCurrentHour() throws {
        let now = try localDate(hour: 12)
        let olderDinner = entry(mealType: "dinner", at: now.addingTimeInterval(-60 * 60))
        let newerSnack = entry(mealType: "snack", at: now.addingTimeInterval(-10 * 60))

        #expect(MealType.resolve(now: now, recentEntries: [olderDinner, newerSnack]) == .lunch)
    }

    @Test func futureEntryDoesNotOverrideCurrentHour() throws {
        let now = try localDate(hour: 8)
        let futureDinner = entry(mealType: "dinner", at: now.addingTimeInterval(60))

        #expect(MealType.resolve(now: now, recentEntries: [futureDinner]) == .breakfast)
    }

    @Test func acceptsLegacySQLiteTimestampForInheritance() throws {
        let now = try localDate(hour: 14)
        let dinner = entry(
            mealType: "dinner",
            at: now.addingTimeInterval(-30 * 60),
            useSQLiteTimestamp: true
        )

        #expect(MealType.resolve(now: now, recentEntries: [dinner]) == .dinner)
    }
}
