import Foundation
import Testing
@testable import DriftCore

/// Tier 0 — boundary contracts for deterministic meal-time parsing and slots.
@Suite struct MealTimingServiceBoundaryTests {

    @Test func parseLocalHourRoundTripsLocalCalendarComponents() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        components.hour = 6
        components.minute = 45

        let date = try #require(Calendar.current.date(from: components))
        let timestamp = DateFormatters.iso8601.string(from: date)

        #expect(MealTimingService.parseLocalHour(timestamp) == 6.75)
        #expect(MealTimingService.parseLocalHour("not-a-timestamp") == nil)
    }

    @Test func medianIgnoresMalformedAndOtherMealEntries() throws {
        let validLunches = ["LUNCH", "lunch", "Lunch"].map {
            entry(meal: $0, hour: 12.25)
        }
        let malformedLunch = FoodEntry(
            foodName: "test",
            servingSizeG: 100,
            calories: 200,
            loggedAt: "invalid",
            mealType: "lunch"
        )
        let breakfast = entry(meal: "breakfast", hour: 8)

        let median = try #require(MealTimingService.medianTime(
            for: .lunch,
            entries: validLunches + [malformedLunch, breakfast],
            minEntries: 3
        ))
        let result = Calendar.current.dateComponents([.hour, .minute], from: median)

        #expect(result.hour == 12)
        #expect(result.minute == 15)
    }

    @Test func patternOffsetWrapsAcrossMidnight() throws {
        let entries = (0..<MealTimingService.minSamplesPerPeriod).map { _ in
            entry(meal: "dinner", hour: 23.75)
        }

        let slots = MealTimingService.reminderSlots(entries: entries, usePatterns: true)
        let dinner = try #require(slots.first { $0.mealPeriod == .dinner })

        #expect(dinner.usedPattern)
        #expect(dinner.medianHour == 23.75)
        #expect(dinner.triggerHour == 0)
        #expect(dinner.triggerMinute == 15)
        #expect(dinner.notificationBody.contains("11:45 PM"))
    }

    private func entry(meal: String, hour: Double) -> FoodEntry {
        let totalMinutes = Int((hour * 60).rounded())
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        components.hour = (totalMinutes / 60) % 24
        components.minute = totalMinutes % 60
        let date = Calendar.current.date(from: components)!

        return FoodEntry(
            foodName: "test",
            servingSizeG: 100,
            calories: 200,
            loggedAt: DateFormatters.iso8601.string(from: date),
            mealType: meal
        )
    }
}
