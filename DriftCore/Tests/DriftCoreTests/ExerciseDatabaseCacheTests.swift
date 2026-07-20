import Foundation
@testable import DriftCore
import Testing

// Tier-0: pure logic — no DB, no LLM, no network.
//
// Guards the blob-validated catalog caches added for #1074 (the exercise picker
// re-decoded the custom-exercise blob and rescanned 952 entries per visible row
// per body evaluation). Two things must hold: the cached results are identical
// to the linear scans they replaced, and the cache cannot go stale when the
// custom blob is mutated from OUTSIDE `addCustomExercises` — factory reset
// (MoreTabView), backup restore (BackupRestorer.applyPreferences) and tests all
// write the key directly, so a writer-invalidated cache would resurrect deleted
// custom exercises.

private let customKey = "drift_custom_exercises"

/// The old `info(for:)` — kept here so the cached implementation is asserted
/// against the exact expression it replaced rather than against hand-written
/// expectations.
private func linearScanInfo(_ name: String) -> ExerciseDatabase.ExerciseInfo? {
    ExerciseDatabase.allWithCustom.first { $0.name.lowercased() == name.lowercased() }
}

// MARK: - Index/scan equivalence

/// The O(1) index keeps the FIRST entry per lowercased name; `first { }` kept
/// the first match too, so the two agree only while no two catalog entries share
/// a lowercased name. If a future catalog import breaks this, `info(for:)` can
/// start returning a different record than it used to — fail loudly here.
@Test @MainActor func catalogHasNoCaseInsensitiveDuplicateNames() {
    let all = ExerciseDatabase.all
    #expect(!all.isEmpty)
    var seen = Set<String>()
    var duplicates: [String] = []
    for exercise in all where !seen.insert(exercise.name.lowercased()).inserted {
        duplicates.append(exercise.name)
    }
    #expect(duplicates.isEmpty, "case-insensitive duplicate catalog names: \(duplicates.prefix(5))")
}

@Test @MainActor func infoMatchesLinearScanAcrossCatalog() {
    // Spread over the catalog rather than the first N — ordering bugs in the
    // index would otherwise hide behind the early entries.
    let all = ExerciseDatabase.all
    let sample = stride(from: 0, to: all.count, by: 37).map { all[$0].name }
    #expect(sample.count > 10)
    for name in sample {
        #expect(ExerciseDatabase.info(for: name)?.name == linearScanInfo(name)?.name)
    }
}

@Test @MainActor func infoIsCaseInsensitiveAndMissesUnknownNames() {
    guard let first = ExerciseDatabase.all.first else { Issue.record("empty catalog"); return }
    #expect(ExerciseDatabase.info(for: first.name.lowercased())?.name == first.name)
    #expect(ExerciseDatabase.info(for: first.name.uppercased())?.name == first.name)
    #expect(ExerciseDatabase.info(for: "CompletelyMadeUpExercise12345") == nil)
    #expect(linearScanInfo("CompletelyMadeUpExercise12345") == nil)
}

@Test @MainActor func bodyPartFallsBackToGuessForUnknownNames() {
    // `bodyPart(for:)` rides on the cached `info(for:)`; the guess path must
    // still engage for names the catalog has never seen.
    #expect(ExerciseDatabase.bodyPart(for: "CompletelyMadeUpExercise12345")
            == ExerciseDatabase.guessBodyPart("CompletelyMadeUpExercise12345"))
    #expect(ExerciseDatabase.bodyPart(for: "Barbell Bench Press Zzz") == "Chest")
}

// MARK: - External-mutation staleness (the reason the cache is blob-keyed)

/// Factory reset removes the key without going through `addCustomExercises`.
/// A writer-invalidated cache would keep serving the deleted exercise.
@Test @MainActor func removingBlobExternallyDropsCustomExerciseFromCaches() {
    let name = "Cache Reset Probe \(UUID().uuidString.prefix(6))"
    let snapshot = UserDefaults.standard.data(forKey: customKey)
    defer { UserDefaults.standard.set(snapshot, forKey: customKey) }

    ExerciseDatabase.addCustomExercise(name: name, bodyPart: "Legs")
    // Warm every cache before the external mutation.
    #expect(ExerciseDatabase.info(for: name) != nil)
    #expect(ExerciseDatabase.allWithCustom.contains { $0.name == name })
    #expect(ExerciseDatabase.customExercises.contains { $0.name == name })

    UserDefaults.standard.removeObject(forKey: customKey)

    #expect(ExerciseDatabase.info(for: name) == nil)
    #expect(!ExerciseDatabase.allWithCustom.contains { $0.name == name })
    #expect(!ExerciseDatabase.customExercises.contains { $0.name == name })
}

/// Backup restore rewrites the blob wholesale. The caches must pick up an
/// exercise they have never seen written through the normal add path.
@Test @MainActor func writingBlobExternallyAddsCustomExerciseToCaches() throws {
    let name = "Cache Restore Probe \(UUID().uuidString.prefix(6))"
    let snapshot = UserDefaults.standard.data(forKey: customKey)
    defer { UserDefaults.standard.set(snapshot, forKey: customKey) }

    // Warm the caches on a blob that does not contain the probe.
    UserDefaults.standard.removeObject(forKey: customKey)
    #expect(ExerciseDatabase.info(for: name) == nil)

    let restored = ExerciseDatabase.ExerciseInfo(
        name: name, bodyPart: "Back", primaryMuscles: ["lats"], secondaryMuscles: [],
        equipment: "barbell", category: "strength", level: "beginner")
    UserDefaults.standard.set(try JSONEncoder().encode([restored]), forKey: customKey)

    #expect(ExerciseDatabase.info(for: name)?.bodyPart == "Back")
    #expect(ExerciseDatabase.allWithCustom.contains { $0.name == name })
    #expect(ExerciseDatabase.bodyPart(for: name) == "Back")
}

/// Repeated reads must stay correct after the blob changes twice — catches a
/// cache that latches the first blob it ever saw.
@Test @MainActor func cachesTrackSuccessiveBlobChanges() {
    let first = "Cache Churn A \(UUID().uuidString.prefix(6))"
    let second = "Cache Churn B \(UUID().uuidString.prefix(6))"
    let snapshot = UserDefaults.standard.data(forKey: customKey)
    defer { UserDefaults.standard.set(snapshot, forKey: customKey) }

    ExerciseDatabase.addCustomExercise(name: first, bodyPart: "Chest")
    #expect(ExerciseDatabase.info(for: first) != nil)

    ExerciseDatabase.addCustomExercise(name: second, bodyPart: "Core")
    #expect(ExerciseDatabase.info(for: first) != nil)
    #expect(ExerciseDatabase.info(for: second)?.bodyPart == "Core")

    UserDefaults.standard.removeObject(forKey: customKey)
    #expect(ExerciseDatabase.info(for: first) == nil)
    #expect(ExerciseDatabase.info(for: second) == nil)
}

/// A custom exercise whose name collides with a catalog entry must stay
/// deduped out of `allWithCustom` (and the index must return the catalog copy),
/// exactly as the uncached implementation did.
@Test @MainActor func customExerciseDoesNotShadowCatalogEntry() {
    guard let catalogEntry = ExerciseDatabase.all.first else { Issue.record("empty catalog"); return }
    let snapshot = UserDefaults.standard.data(forKey: customKey)
    defer { UserDefaults.standard.set(snapshot, forKey: customKey) }

    ExerciseDatabase.addCustomExercise(name: catalogEntry.name.lowercased(), bodyPart: "Core")

    let matches = ExerciseDatabase.allWithCustom.filter { $0.name.lowercased() == catalogEntry.name.lowercased() }
    #expect(matches.count == 1)
    #expect(ExerciseDatabase.info(for: catalogEntry.name)?.bodyPart == catalogEntry.bodyPart)
    #expect(ExerciseDatabase.info(for: catalogEntry.name)?.name == linearScanInfo(catalogEntry.name)?.name)
}
