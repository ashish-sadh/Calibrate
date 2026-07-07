import Foundation
import Testing
@testable import DriftCore

/// Tier-0 for the Apple Health nutrition write-back plan (#934): the spec
/// builder decides exactly WHAT gets written for an entry — one sample per
/// positive macro, stable per-entry sync identifiers (edits replace, deletes
/// target only Drift's samples), timestamps from loggedAt.
struct NutritionHealthSyncTests {

    private func entry(id: Int64? = 7, calories: Double = 250, protein: Double = 12,
                       carbs: Double = 30, fat: Double = 9, fiber: Double = 4,
                       loggedAt: String = "2026-07-07T08:30:00Z",
                       date: String? = "2026-07-07") -> FoodEntry {
        FoodEntry(id: id, mealLogId: 0, foodId: nil, foodName: "test",
                  servingSizeG: 100, servings: 1, calories: calories,
                  proteinG: protein, carbsG: carbs, fatG: fat, fiberG: fiber,
                  createdAt: loggedAt, loggedAt: loggedAt, date: date, mealType: "breakfast")
    }

    @Test func specsCoverAllFiveMacros() {
        let specs = NutritionHealthSync.specs(for: entry())
        #expect(specs.count == 5)
        #expect(specs.map(\.kind) == [.energyKcal, .proteinG, .carbsG, .fatG, .fiberG])
        #expect(specs.first?.value == 250)
    }

    @Test func zeroMacrosAreOmitted() {
        // 0g fiber must not write a 0-valued Health sample.
        let specs = NutritionHealthSync.specs(for: entry(fiber: 0))
        #expect(specs.count == 4)
        #expect(!specs.contains { $0.kind == .fiberG })
    }

    @Test func entryWithoutIdProducesNothing() {
        // No DB id = no stable sync identity — never write orphan samples.
        #expect(NutritionHealthSync.specs(for: entry(id: nil)).isEmpty)
    }

    @Test func syncIdentifiersAreStablePerEntryAndKind() {
        let specs = NutritionHealthSync.specs(for: entry(id: 42))
        #expect(specs.first?.syncIdentifier == "drift-food-42-kcal")
        #expect(Set(specs.map(\.syncIdentifier)).count == specs.count, "identifiers must be unique per sample")
        // Deletion covers every kind, including macros that were 0 at write time.
        #expect(NutritionHealthSync.syncIdentifiers(entryId: 42).count == 5)
        #expect(NutritionHealthSync.syncIdentifiers(entryId: 42).allSatisfy { $0.hasPrefix("drift-food-42-") })
    }

    @Test func timestampUsesLoggedAtWhenParseable() {
        let ts = NutritionHealthSync.timestamp(for: entry(loggedAt: "2026-07-07T08:30:00Z"))
        #expect(ts == ISO8601DateFormatter().date(from: "2026-07-07T08:30:00Z"))
    }

    @Test func timestampFallsBackToNoonOnEntryDay() {
        // Unparseable loggedAt → noon on the entry's day, never midnight
        // (day-boundary ambiguity in Health's daily buckets).
        let ts = NutritionHealthSync.timestamp(for: entry(loggedAt: "garbage", date: "2026-07-05"))
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour], from: ts)
        #expect(comps.day == 5)
        #expect(comps.hour == 12)
    }
}
