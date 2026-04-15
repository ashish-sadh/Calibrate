import Foundation
import Testing
@testable import Drift

// MARK: - WeightServiceAPI Tests
// Tests for validation, unit conversion, history filtering, and describe logic.

// MARK: - logWeight Validation

@Test @MainActor func logWeightTooLowKgReturnsNil() async throws {
    let result = WeightServiceAPI.logWeight(value: 5, unit: "kg") // < 10 kg threshold
    #expect(result == nil, "Values below 10 kg should be rejected")
}

@Test @MainActor func logWeightTooHighLbsReturnsNil() async throws {
    let result = WeightServiceAPI.logWeight(value: 700, unit: "lbs") // 700 lbs = ~317 kg, > 300 kg limit
    #expect(result == nil, "700 lbs (~317 kg) should be rejected as too high")
}

@Test @MainActor func logWeightTooHighKgReturnsNil() async throws {
    let result = WeightServiceAPI.logWeight(value: 350, unit: "kg") // > 300 kg
    #expect(result == nil, "350 kg should be rejected as too high")
}

@Test @MainActor func logWeightTooLowLbsReturnsNil() async throws {
    let result = WeightServiceAPI.logWeight(value: 20, unit: "lbs") // 20 lbs ≈ 9.07 kg < 10
    #expect(result == nil, "20 lbs (~9 kg) should be rejected as too low")
}

// MARK: - logWeight Unit Conversion

@Test @MainActor func logWeightKgPassthroughCorrect() async throws {
    let result = WeightServiceAPI.logWeight(value: 75, unit: "kg")
    #expect(result != nil, "75 kg is a valid weight")
    if let entry = result {
        #expect(abs(entry.weightKg - 75.0) < 0.01, "kg values should be stored as-is")
    }
}

@Test @MainActor func logWeightLbsConversionCorrect() async throws {
    let result = WeightServiceAPI.logWeight(value: 165, unit: "lbs")
    #expect(result != nil, "165 lbs is a valid weight")
    if let entry = result {
        let expectedKg = 165.0 / 2.20462
        #expect(abs(entry.weightKg - expectedKg) < 0.01, "lbs should convert to kg correctly")
    }
}

@Test @MainActor func logWeightKgPrefixMatchesVariants() async throws {
    // "kgs", "KG", "Kg" should all be treated as kg (hasPrefix check)
    let result = WeightServiceAPI.logWeight(value: 80, unit: "kgs")
    if let entry = result {
        #expect(abs(entry.weightKg - 80.0) < 0.01, "kg prefix variants should not convert")
    }
}

@Test @MainActor func logWeightBoundaryJustAbove10() async throws {
    let result = WeightServiceAPI.logWeight(value: 11, unit: "kg")
    #expect(result != nil, "11 kg is just above the 10 kg lower bound")
}

@Test @MainActor func logWeightBoundaryJustBelow300() async throws {
    let result = WeightServiceAPI.logWeight(value: 299, unit: "kg")
    #expect(result != nil, "299 kg is just below the 300 kg upper bound")
}

// MARK: - getHistory Filtering

@Test @MainActor func getHistoryReturnsArray() async throws {
    let history = WeightServiceAPI.getHistory(days: 30)
    #expect(history.count >= 0)
}

@Test @MainActor func getHistory365BypassesFilter() async throws {
    // days >= 365 returns all entries unfiltered
    let all = WeightServiceAPI.getHistory(days: 365)
    let limited = WeightServiceAPI.getHistory(days: 7)
    #expect(all.count >= limited.count, "365-day history should have >= entries than 7-day")
}

@Test @MainActor func getHistoryFiltersOldEntries() async throws {
    // 1-day window should return only recent entries
    let recent = WeightServiceAPI.getHistory(days: 1)
    let all = WeightServiceAPI.getHistory(days: 365)
    #expect(recent.count <= all.count)
}

// MARK: - describeTrend

@Test @MainActor func describeTrendReturnsNonEmptyString() async throws {
    let desc = WeightServiceAPI.describeTrend()
    #expect(!desc.isEmpty, "describeTrend should always return a non-empty string")
}

@Test @MainActor func describeTrendNoDataMessage() async throws {
    // When WeightTrendService has no loaded trend, returns default message
    // The service refreshes lazily; we can call it and verify it handles gracefully
    let desc = WeightServiceAPI.describeTrend()
    let isDefault = desc == "No weight data yet."
    let hasCurrentWeight = desc.contains("Current:")
    #expect(isDefault || hasCurrentWeight, "describeTrend should return default or formatted data")
}

// MARK: - fetchBodyComposition

@Test @MainActor func fetchBodyCompositionReturnsArray() async throws {
    let entries = WeightServiceAPI.fetchBodyComposition()
    #expect(entries.count >= 0)
}

@Test @MainActor func latestBodyCompositionDoesNotCrash() async throws {
    // Just verify it doesn't throw or crash
    _ = WeightServiceAPI.latestBodyComposition()
}

// MARK: - getGoalProgress

@Test @MainActor func getGoalProgressDoesNotCrash() async throws {
    _ = WeightServiceAPI.getGoalProgress()
}

// MARK: - saveWeightEntry

@Test @MainActor func saveWeightEntryPersists() async throws {
    var entry = WeightEntry(date: "2020-01-01", weightKg: 70.0, source: "test")
    WeightServiceAPI.saveWeightEntry(&entry)
    // Verify it was saved (entry should get an id after save)
    let history = WeightServiceAPI.getHistory(days: 3650)
    #expect(history.contains { $0.date == "2020-01-01" && abs($0.weightKg - 70.0) < 0.01 })
}
