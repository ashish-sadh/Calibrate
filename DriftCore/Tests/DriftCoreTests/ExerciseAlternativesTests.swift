import Foundation
import Testing
@testable import DriftCore

/// Tier-0 for mid-workout exercise substitution.
///
/// "Swap the squats" is asked because something is wrong — the rack is taken, a
/// knee is complaining, the weight isn't there. So a substitute has to train the
/// SAME thing (swapping a squat for a curl is not a swap, it's a different
/// workout) and be doable with the equipment actually present.
struct ExerciseAlternativesTests {

    @Test func aSubstituteTrainsTheSameBodyPart() {
        let subs = ExerciseAlternatives.suggestions(for: "Barbell Squat")
        #expect(!subs.isEmpty, "the catalog has plenty of leg work")
        guard let original = ExerciseDatabase.info(for: "Barbell Squat")
                ?? ExerciseDatabase.match(name: "Barbell Squat") else { return }
        let wanted = Set(original.primaryMuscles.map { $0.lowercased() })
        for sub in subs {
            let primary = Set(sub.primaryMuscles.map { $0.lowercased() })
            let sameArea = !primary.isDisjoint(with: wanted)
                || sub.bodyPart.lowercased() == original.bodyPart.lowercased()
            #expect(sameArea, "\(sub.name) trains nothing the squat trains")
        }
    }

    /// Never offer the lift they're trying to get away from.
    @Test func theOriginalIsNeverItsOwnSubstitute() {
        let subs = ExerciseAlternatives.suggestions(for: "Barbell Squat")
        #expect(!subs.contains { $0.name == "Barbell Squat" })
    }

    /// Offering someone the lift they're already doing three sets of is the one
    /// answer guaranteed to be useless.
    @Test func exercisesAlreadyInTheSessionAreExcluded() {
        let all = ExerciseAlternatives.suggestions(for: "Barbell Squat", limit: 3)
        guard let first = all.first else { return }
        let without = ExerciseAlternatives.suggestions(
            for: "Barbell Squat", excluding: [first.name], limit: 3)
        #expect(!without.contains { $0.name == first.name })
    }

    /// A home profile must not be told to use a leg-press machine.
    @Test func equipmentFilterIsHonoured() {
        let bodyweightOnly = ExerciseAlternatives.suggestions(
            for: "Barbell Squat", equipment: ["body only"], limit: 10)
        for sub in bodyweightOnly {
            #expect(ExerciseDatabase.isDoable(sub, with: ["body only"]),
                    "\(sub.name) needs kit this profile doesn't have")
        }
    }

    /// Empty equipment means "no filter" — an unknown gym is not a reason to
    /// refuse to answer.
    @Test func noEquipmentSetMeansNoFilter() {
        let unfiltered = ExerciseAlternatives.suggestions(for: "Barbell Squat", limit: 10)
        let filtered = ExerciseAlternatives.suggestions(
            for: "Barbell Squat", equipment: ["body only"], limit: 10)
        #expect(unfiltered.count >= filtered.count)
    }

    /// A full primary-muscle match should outrank a mere same-body-part one.
    @Test func aCloserMatchRanksHigher() {
        guard let squat = ExerciseDatabase.info(for: "Barbell Squat")
                ?? ExerciseDatabase.match(name: "Barbell Squat") else { return }
        let wanted = Set(squat.primaryMuscles.map { $0.lowercased() })
        let subs = ExerciseAlternatives.suggestions(for: "Barbell Squat", limit: 5)
        let scores = subs.map {
            ExerciseAlternatives.score($0, against: squat, wantedPrimary: wanted)
        }
        #expect(scores == scores.sorted(by: >), "results must come back best-first")
    }

    /// Stable between asks — a list that reshuffles every time reads as broken.
    @Test func theOrderIsStable() {
        let a = ExerciseAlternatives.suggestions(for: "Bench Press", limit: 5).map(\.name)
        let b = ExerciseAlternatives.suggestions(for: "Bench Press", limit: 5).map(\.name)
        #expect(a == b)
    }

    @Test func anUnknownExerciseYieldsNothingRatherThanGarbage() {
        #expect(ExerciseAlternatives.suggestions(for: "zzzz not a lift").isEmpty)
        #expect(ExerciseAlternatives.best(for: "zzzz not a lift") == nil)
    }

    /// `best` is just the top of the list — one call site, one ranking.
    @Test func bestIsTheHeadOfTheList() {
        let top = ExerciseAlternatives.suggestions(for: "Bench Press", limit: 1).first?.name
        #expect(ExerciseAlternatives.best(for: "Bench Press")?.name == top)
    }
}
