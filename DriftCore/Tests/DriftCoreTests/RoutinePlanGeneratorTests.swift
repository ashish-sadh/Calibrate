import Foundation
@testable import DriftCore
import Testing

// Tier-0 tests for RoutinePlanGenerator — the pure core of the Coach
// interview's routine generation (prompt, decode, grounding, offline
// fallback). The actual Nebius call lives in the iOS service and is not
// exercised here.

// MARK: - Decode

@Test func decode_validJSONRoundTrips() {
    let raw = """
    {"days":[{"name":"Push","exercises":[{"name":"Bench Press","sets":3,"reps":"8-12"}]}]}
    """
    let days = RoutinePlanGenerator.decode(raw)
    #expect(days?.count == 1)
    #expect(days?.first?.name == "Push")
    #expect(days?.first?.exercises.first == .init(name: "Bench Press", sets: 3, reps: "8-12"))
}

@Test func decode_extractsJSONFromProse() {
    let raw = """
    Here is your plan:
    {"days":[{"name":"Full Body","exercises":[{"name":"Squat","sets":3,"reps":"5"}]}]}
    Enjoy!
    """
    #expect(RoutinePlanGenerator.decode(raw)?.first?.name == "Full Body")
}

@Test func decode_rejectsGarbageAndOutOfBounds() {
    #expect(RoutinePlanGenerator.decode("no json here") == nil)
    #expect(RoutinePlanGenerator.decode("{\"days\":[]}") == nil)
    let eightDays = (1...8).map { "{\"name\":\"D\($0)\",\"exercises\":[]}" }.joined(separator: ",")
    #expect(RoutinePlanGenerator.decode("{\"days\":[\(eightDays)]}") == nil)
}

// MARK: - Grounding

@MainActor
@Test func grounded_dropsHallucinatedNamesAndThinDays() {
    let days = [
        RoutinePlanGenerator.PlannedDay(name: "Push", exercises: [
            .init(name: "Barbell Bench Press - Medium Grip", sets: 3, reps: "8-12"),
            .init(name: "Pushup", sets: 9, reps: "12"),
            .init(name: "Quantum Flux Press", sets: 3, reps: "8"),
        ]),
        RoutinePlanGenerator.PlannedDay(name: "Fake Day", exercises: [
            .init(name: "Made Up Move", sets: 3, reps: "8"),
            .init(name: "Another Fake", sets: 3, reps: "8"),
        ]),
    ]
    let grounded = RoutinePlanGenerator.grounded(days)
    #expect(grounded?.count == 1, "day with <2 real exercises must drop")
    let push = grounded?.first
    #expect(push?.exercises.count == 2, "hallucinated name must drop")
    #expect(push?.exercises.allSatisfy { (1...5).contains($0.sets) } == true, "sets clamp to 1-5")
}

@MainActor
@Test func grounded_nilWhenNothingSurvives() {
    let days = [RoutinePlanGenerator.PlannedDay(name: "X", exercises: [
        .init(name: "Totally Invented Exercise Zeta", sets: 3, reps: "8"),
    ])]
    #expect(RoutinePlanGenerator.grounded(days) == nil)
}

// MARK: - Fallback plan

@MainActor
@Test func fallbackPlan_threeDaysIsPPL() {
    let plan = RoutinePlanGenerator.fallbackPlan(
        profile: TrainingProfile(daysPerWeek: 3))
    #expect(plan.map(\.name) == ["Push", "Pull", "Legs"])
    #expect(plan.allSatisfy { !$0.exercises.isEmpty })
}

@MainActor
@Test func fallbackPlan_fourDaysCyclesUpperLower() {
    let plan = RoutinePlanGenerator.fallbackPlan(
        profile: TrainingProfile(daysPerWeek: 4))
    #expect(plan.map(\.name) == ["Upper", "Lower", "Upper B", "Lower B"])
}

@MainActor
@Test func fallbackPlan_homeProfileUsesOnlyDoableExercises() {
    let profile = TrainingProfile(location: .home, equipment: ["dumbbell"], daysPerWeek: 3)
    let plan = RoutinePlanGenerator.fallbackPlan(profile: profile)
    let allowed: Set<String> = ["dumbbell", "body only"]
    for day in plan {
        for ex in day.exercises {
            let equipment = ExerciseDatabase.info(for: ex.name)?.equipment
            #expect(equipment == nil || allowed.contains(equipment!),
                    "\(ex.name) (\(equipment ?? "?")) not doable at home with dumbbells")
        }
    }
}

// MARK: - Prompt

@MainActor
@Test func prompt_carriesProfileAndPoolAndRules() {
    let profile = TrainingProfile(experience: .beginner, location: .home,
                                  equipment: ["dumbbell"], constraints: ["left knee pain"],
                                  daysPerWeek: 3, sessionMinutes: 45, priority: "back")
    let pool = ["Chest": ["Dumbbell Bench Press"], "Back": ["Dumbbell Row"]]
    let p = RoutinePlanGenerator.buildPrompt(profile: profile, goalLine: "fat loss", pool: pool)
    #expect(p.contains("3-day"))
    #expect(p.contains("beginner"))
    #expect(p.contains("fat loss"))
    #expect(p.contains("left knee pain"))
    #expect(p.contains("Dumbbell Bench Press"))
    #expect(p.contains("ONLY"))
    #expect(p.contains("\"days\""))
}

@MainActor
@Test func candidatePool_respectsEquipmentRestriction() {
    let profile = TrainingProfile(location: .home, equipment: ["bands"])
    let pool = RoutinePlanGenerator.candidatePool(profile: profile)
    let allowed: Set<String> = ["bands", "body only"]
    for (_, names) in pool {
        for name in names {
            let equipment = ExerciseDatabase.info(for: name)?.equipment
            #expect(equipment == nil || allowed.contains(equipment!),
                    "\(name) leaked into a bands-only pool")
        }
    }
}
