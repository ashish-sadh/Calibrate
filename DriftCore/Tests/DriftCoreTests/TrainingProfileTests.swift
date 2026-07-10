import Foundation
@testable import DriftCore
import Testing

// Tier-0 tests for TrainingProfile (interview answers → workout generation)
// and the ExerciseDatabase equipment filter it drives.

// MARK: - Persistence (serialized — one UserDefaults key)

@Suite(.serialized) struct TrainingProfilePersistence {

    @Test func roundTrip() {
        defer { TrainingProfile.clear() }
        let profile = TrainingProfile(
            experience: .intermediate, location: .home,
            equipment: ["dumbbell", "bands"], constraints: ["left knee pain"],
            medicalClearance: true, daysPerWeek: 3, sessionMinutes: 45,
            priority: "shoulders")
        profile.save()
        #expect(TrainingProfile.load() == profile)
    }

    @Test func loadReturnsNilWhenUnset() {
        TrainingProfile.clear()
        #expect(TrainingProfile.load() == nil)
    }
}

// MARK: - Derived state (pure)

@Test func restrictsEquipment_homeAlwaysRestricts() {
    #expect(TrainingProfile(location: .home).restrictsEquipment)
    #expect(TrainingProfile(location: .home, equipment: ["dumbbell"]).restrictsEquipment)
}

@Test func restrictsEquipment_gymNeverRestricts() {
    #expect(!TrainingProfile(location: .gym).restrictsEquipment)
    // Explicit gym overrides a stale equipment list
    #expect(!TrainingProfile(location: .gym, equipment: ["dumbbell"]).restrictsEquipment)
}

@Test func restrictsEquipment_equipmentListWithoutLocationRestricts() {
    #expect(TrainingProfile(equipment: ["bands"]).restrictsEquipment)
    #expect(!TrainingProfile().restrictsEquipment)
}

@Test func summaryReadsAsOneLine() {
    let p = TrainingProfile(experience: .beginner, location: .home,
                            equipment: ["dumbbell"], constraints: ["postpartum"],
                            daysPerWeek: 3)
    let s = p.summary
    #expect(s.contains("beginner"))
    #expect(s.contains("home"))
    #expect(s.contains("dumbbell"))
    #expect(s.contains("3 days/week"))
    #expect(s.contains("watch: postpartum"))
}

// MARK: - Equipment normalization (pure)

@Test func normalizeEquipment_mapsCommonPhrases() {
    let slugs = TrainingProfile.normalizeEquipment(
        "I have a pair of dumbbells, resistance bands and a pull-up bar at home")
    #expect(Set(slugs) == ["dumbbell", "bands", "other"])
}

@Test func normalizeEquipment_nothingMapsToEmpty() {
    #expect(TrainingProfile.normalizeEquipment("nothing, just my body").isEmpty)
}

@Test func normalizedSlugsAreCatalogSlugs() {
    let all = TrainingProfile.normalizeEquipment(
        "dumbbell barbell kettlebell band cable machine medicine ball swiss ball foam roll ez bar trx")
    for slug in all {
        #expect(ExerciseDatabase.equipmentSlugs.contains(slug), "\(slug) is not a catalog slug")
    }
}

// MARK: - ExerciseDatabase equipment filter

@Test func isDoable_bodyweightAlwaysDoable() {
    let pushUp = ExerciseDatabase.all.first { $0.equipment == "body only" }
    #expect(pushUp != nil)
    #expect(ExerciseDatabase.isDoable(pushUp!, with: ["dumbbell"]))
    #expect(ExerciseDatabase.isDoable(pushUp!, with: ["body only"]))
}

@Test func isDoable_emptySetMeansUnrestricted() {
    let barbell = ExerciseDatabase.all.first { $0.equipment == "barbell" }
    #expect(barbell != nil)
    #expect(ExerciseDatabase.isDoable(barbell!, with: []))
}

@Test func isDoable_missingEquipmentExcludes() {
    let barbell = ExerciseDatabase.all.first { $0.equipment == "barbell" }
    #expect(barbell != nil)
    #expect(!ExerciseDatabase.isDoable(barbell!, with: ["dumbbell", "body only"]))
}

@Test func filtered_homeSetupKeepsOnlyDoable() {
    let home: Set<String> = ["dumbbell", "bands", "body only"]
    let pool = ExerciseDatabase.filtered(byEquipment: home)
    #expect(!pool.isEmpty)
    #expect(pool.allSatisfy { home.contains($0.equipment) || $0.equipment == "body only" })
    // Sanity: a real home pool is still big enough to program from
    #expect(pool.count > 100)
}
