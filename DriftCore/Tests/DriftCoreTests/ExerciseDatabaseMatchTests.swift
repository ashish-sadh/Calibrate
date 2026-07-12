import Foundation
@testable import DriftCore
import Testing

// Tier-0 tests for ExerciseDatabase.match(name:) — the grounding gate that
// resolves a spoken/parsed exercise name to a canonical library entry, or
// returns nil so voice logging can flag a garbled/novel name instead of
// silently inventing an exercise (the "two chest ups → squats + bench" bug).

@Test func match_exactNameCaseInsensitive() {
    #expect(ExerciseDatabase.match(name: "Plank")?.name == "Plank")
    #expect(ExerciseDatabase.match(name: "plank")?.name == "Plank")
    #expect(ExerciseDatabase.match(name: "PLANK")?.name == "Plank")
}

@Test func match_pluralResolvesToSingular() {
    // "squats" must map to a real squat entry despite the trailing 's'.
    let hit = ExerciseDatabase.match(name: "squats")
    #expect(hit != nil)
    #expect(hit?.name.lowercased().contains("squat") == true)
}

@Test func match_singleWordPicksMostSpecific() {
    // Among many "... Squat" names, the bare "Squat" (fewest extra words) wins.
    #expect(ExerciseDatabase.match(name: "squat")?.name == "Squat")
}

@Test func match_multiWordCovered() {
    let bench = ExerciseDatabase.match(name: "bench press")
    #expect(bench != nil)
    #expect(bench?.name.lowercased().contains("bench") == true)
    #expect(bench?.name.lowercased().contains("press") == true)

    let dead = ExerciseDatabase.match(name: "deadlift")
    #expect(dead?.name.lowercased().contains("deadlift") == true)
}

@Test func match_garbledNameReturnsNil() {
    // The reported regression: "chest ups" is not a real movement — no single
    // catalog name covers BOTH "chest" and "ups", so we must flag, not invent.
    #expect(ExerciseDatabase.match(name: "chest ups") == nil)
}

@Test func match_nonsenseReturnsNil() {
    #expect(ExerciseDatabase.match(name: "qwerty zzz") == nil)
    #expect(ExerciseDatabase.match(name: "") == nil)
    #expect(ExerciseDatabase.match(name: "x") == nil)
}

@Test func match_extraDescriptiveWordsAreFlagged() {
    // "heavy bench" adds a word that's not in any canonical name → flagged so the
    // user can confirm, rather than silently dropping "heavy".
    #expect(ExerciseDatabase.match(name: "heavy super bench thing") == nil)
}

// MARK: - trackingType (#925 — per-exercise time-vs-reps classification)

@Test func trackingType_declaredDrillsAreTimeBased() {
    // Agility drills are declared time-based as data (an explicit name set), not
    // matched by a fuzzy substring — the fix the issue asked for.
    #expect(ExerciseDatabase.trackingType(for: "Ladder Drill") == .time)
    #expect(ExerciseDatabase.trackingType(for: "Agility Ladder") == .time)
    #expect(ExerciseDatabase.classifyTrackingType("Speed Ladder") == .time)
}

@Test func trackingType_holdFamiliesStayTimeBased() {
    // Family roots kept verbatim from the prior keyword list → no duration
    // exercise regresses to reps.
    for name in ["Plank", "Side Plank", "Wall Sit", "Dead Hang", "Farmer's Walk"] {
        #expect(ExerciseDatabase.trackingType(for: name) == .time, "\(name) should be time-based")
    }
}

@Test func trackingType_commonLiftsAreReps() {
    for name in ["Bench Press", "Back Squat", "Deadlift", "Bicep Curl", "Overhead Press"] {
        #expect(ExerciseDatabase.trackingType(for: name) == .reps, "\(name) should be reps-based")
    }
}

@Test func exerciseInfo_carriesExplicitTrackingType() {
    // The exercise model distinguishes tracking type as a per-exercise enum.
    let timed = ExerciseDatabase.ExerciseInfo(
        name: "x", bodyPart: "Core", primaryMuscles: [], secondaryMuscles: [],
        equipment: "other", category: "strength", level: "intermediate", trackingType: .time)
    #expect(timed.trackingType == .time)
}

@Test func exerciseInfo_catalogTrackingTypeDecodes() {
    // 2026-07-09: genuinely time-based catalog exercises now DECLARE
    // trackingType=time in the JSON (the data-driven timer/reps fix); the
    // rest decode to nil (⇒ reps). Verify both decode cleanly and the
    // declared-time set is present and sane.
    let all = ExerciseDatabase.all
    #expect(!all.isEmpty)
    let timed = all.filter { $0.trackingType == .time }
    #expect(timed.count >= 20, "expected the curated time allow-list, got \(timed.count)")
    #expect(timed.contains { $0.name == "Plank" })
    #expect(timed.contains { $0.name == "Farmer's Walk" })
    // No rep movement was wrongly tagged time in the data.
    #expect(!timed.contains { $0.name == "Walking Lunge" })
    #expect(!timed.contains { $0.name == "Hang Clean" })
}

// MARK: - Catalog dedup guard (#929)

@Test func catalogHasNoExactDuplicateNames() {
    // The 2026-07-07 audit found the "duplicates" were mostly legitimate
    // variants (Turkish Get-Up lunge vs squat style); the one true dup —
    // Front Squat (Clean Grip) ≡ Front Squat — was merged. This guard keeps
    // exact-name dups from creeping back in.
    let names = ExerciseDatabase.all.map { $0.name.lowercased() }
    #expect(names.count == Set(names).count, "exercises.json has exact-name duplicates")
}

@Test func mergedDuplicatesStayMerged() {
    #expect(ExerciseDatabase.all.first { $0.name == "Front Squat (Clean Grip)" } == nil)
    #expect(ExerciseDatabase.all.first { $0.name == "Front Squat" } != nil,
            "the kept canonical entry must still exist")
}

// MARK: - Pose asset mapping (#929)

@Test func poseAssetNameDerivesFromImageUrl() {
    #expect(ExercisePoses.assetBaseName(
        fromImageUrl: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Front_Squat/0.jpg"
    ) == "Front_Squat")
    #expect(ExercisePoses.assetBaseName(fromImageUrl: nil) == nil)
    #expect(ExercisePoses.assetBaseName(fromImageUrl: "https://example.com/other.jpg") == nil)
    #expect(ExercisePoses.assetBaseName(fromImageUrl: "free-exercise-db/main/exercises//0.jpg") == nil)
}

@Test func mostCatalogEntriesHavePoseMapping() {
    // 931/959 at ingestion (2026-07-07). Guard against the mapping silently
    // collapsing — e.g. a catalog refresh rewriting imageUrls off-dataset.
    let mapped = ExerciseDatabase.all.filter {
        ExercisePoses.assetBaseName(fromImageUrl: $0.imageUrl) != nil
    }
    #expect(mapped.count >= 900, "pose mapping collapsed: \(mapped.count)/\(ExerciseDatabase.all.count)")
}

// MARK: - Template packages (#940): every exercise resolves with visuals

@Test func customExerciseTableUsesValidMuscleSlugsAndAssets() {
    let validSlugs: Set<String> = ["abdominals", "abductors", "adductors", "biceps", "calves",
                                   "chest", "forearms", "glutes", "hamstrings", "lats",
                                   "lower back", "middle back", "neck", "quadriceps",
                                   "shoulders", "traps", "triceps"]
    for c in DefaultTemplates.customExercises {
        for m in c.muscles ?? [] {
            #expect(validSlugs.contains(m), "\(c.name): '\(m)' is not a catalog muscle slug — the diagram can't highlight it")
        }
        if let dir = c.fedDir {
            let url = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/\(dir)/0.jpg"
            #expect(ExercisePoses.assetBaseName(fromImageUrl: url) == dir,
                    "\(c.name): fedDir '\(dir)' does not round-trip through the pose mapper")
        }
    }
}

@Test func packageIITemplatesDecodeAndResolve() throws {
    let templates = DefaultTemplates.packageII
    #expect(templates.count == 6)
    let customNames = Set(DefaultTemplates.customExercises.map { $0.name.lowercased() })
    let catalogNames = Set(ExerciseDatabase.all.map { $0.name.lowercased() })
    for t in templates {
        let exercises = try JSONDecoder().decode(
            [WorkoutTemplate.TemplateExercise].self, from: Data(t.exercisesJson.utf8))
        #expect(!exercises.isEmpty, "\(t.name) has no exercises")
        for ex in exercises {
            let n = ex.name.lowercased()
            #expect(customNames.contains(n) || catalogNames.contains(n),
                    "\(t.name): '\(ex.name)' resolves to neither catalog nor custom registry — no diagram/pose")
        }
    }
}

@Test func bandPackageTemplatesDecodeAndResolve() throws {
    // The whiteboard band program — Package I since the 2026-07-11 renumber.
    let templates = DefaultTemplates.packageI
    #expect(templates.count == 2)
    #expect(templates.map(\.name) == ["Resistance Band A", "Resistance Band B"])
    let customNames = Set(DefaultTemplates.customExercises.map { $0.name.lowercased() })
    let catalogNames = Set(ExerciseDatabase.all.map { $0.name.lowercased() })
    for t in templates {
        let exercises = try JSONDecoder().decode(
            [WorkoutTemplate.TemplateExercise].self, from: Data(t.exercisesJson.utf8))
        #expect(exercises.count == 5, "\(t.name) should have 5 exercises")
        for ex in exercises {
            let n = ex.name.lowercased()
            #expect(customNames.contains(n) || catalogNames.contains(n),
                    "\(t.name): '\(ex.name)' resolves to neither catalog nor custom registry — no diagram/pose")
        }
    }
}

// Field report 2026-07-09: seeded templates arrived pre-starred ("why is II
// fav randomly on install"). Favorites are the user's call — no package may
// ship one.
@Test func noPackageTemplateArrivesFavorited() {
    for t in DefaultTemplates.packageI + DefaultTemplates.packageII + DefaultTemplates.packageIV {
        #expect(!t.isFavorite, "\(t.name) is seeded as favorite")
    }
}

@Test func packageIVTemplateExercisesAllResolve() throws {
    // The original curated programs — Package IV since the 2026-07-11 renumber.
    let customNames = Set(DefaultTemplates.customExercises.map { $0.name.lowercased() })
    let catalogNames = Set(ExerciseDatabase.all.map { $0.name.lowercased() })
    for t in DefaultTemplates.packageIV {
        let exercises = try JSONDecoder().decode(
            [WorkoutTemplate.TemplateExercise].self, from: Data(t.exercisesJson.utf8))
        for ex in exercises {
            let n = ex.name.lowercased()
            #expect(customNames.contains(n) || catalogNames.contains(n),
                    "\(t.name): '\(ex.name)' resolves to neither catalog nor custom registry")
        }
    }
}

@Test @MainActor func addCustomExerciseUpgradesLegacyEntriesInPlace() {
    let name = "Test Upgrade Exercise \(UUID().uuidString.prefix(6))"
    // No remove API — snapshot/restore the persisted blob around the test.
    let key = "drift_custom_exercises"
    let snapshot = UserDefaults.standard.data(forKey: key)
    defer { UserDefaults.standard.set(snapshot, forKey: key) }
    // Legacy registration: no muscles, no imageUrl (pre-#941 builds).
    ExerciseDatabase.addCustomExercise(name: name, bodyPart: "Legs")
    // Re-registration with the richer fields must fill them in place —
    // existing installs never re-tap the load button.
    ExerciseDatabase.addCustomExercise(
        name: name, bodyPart: "Legs",
        primaryMuscles: ["quadriceps"],
        imageUrl: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Goblet_Squat/0.jpg")
    let info = ExerciseDatabase.allWithCustom.first { $0.name == name }
    #expect(info?.primaryMuscles == ["quadriceps"])
    #expect(ExercisePoses.assetBaseName(fromImageUrl: info?.imageUrl) == "Goblet_Squat")
}

// Registry pose fixes must reach installs that stored the old URL (the
// B-Stance RDL fedDir moved from a minted asset to Band_Good_Morning,
// 2026-07-09); fill-only would pin the first-ever URL forever. Without
// the authoritative flag the stored value still wins.
@Test @MainActor func authoritativeImageUrlOverwritesStaleRegistryValue() {
    let name = "Test Authoritative Exercise \(UUID().uuidString.prefix(6))"
    let key = "drift_custom_exercises"
    let snapshot = UserDefaults.standard.data(forKey: key)
    defer { UserDefaults.standard.set(snapshot, forKey: key) }
    let old = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Old_Dir/0.jpg"
    let new = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Band_Good_Morning/0.jpg"
    ExerciseDatabase.addCustomExercise(name: name, bodyPart: "Legs", imageUrl: old)

    ExerciseDatabase.addCustomExercise(name: name, bodyPart: "Legs", imageUrl: new)
    var info = ExerciseDatabase.allWithCustom.first { $0.name == name }
    #expect(ExercisePoses.assetBaseName(fromImageUrl: info?.imageUrl) == "Old_Dir")

    ExerciseDatabase.addCustomExercise(name: name, bodyPart: "Legs", imageUrl: new, imageUrlAuthoritative: true)
    info = ExerciseDatabase.allWithCustom.first { $0.name == name }
    #expect(ExercisePoses.assetBaseName(fromImageUrl: info?.imageUrl) == "Band_Good_Morning")
}
