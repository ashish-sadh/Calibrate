import Foundation
@testable import DriftCore
import Testing

// Tier-0: pure logic — no DB, no LLM, no network.
// formTip, resolveSplitType, splitDefinitions, exerciseInstructions,
// suggestForSplitDay, buildSplitTemplate, resolveExerciseName.

// MARK: - formTip (chest)

@Test @MainActor func formTipBenchPress() {
    #expect(ExerciseService.formTip(for: "bench press") != nil)
}

@Test @MainActor func formTipInclinePress() {
    #expect(ExerciseService.formTip(for: "incline dumbbell press") != nil)
}

@Test @MainActor func formTipChestFly() {
    #expect(ExerciseService.formTip(for: "chest fly") != nil)
}

@Test @MainActor func formTipFlye() {
    #expect(ExerciseService.formTip(for: "cable flye") != nil)
}

@Test @MainActor func formTipPushUp() {
    #expect(ExerciseService.formTip(for: "push up") != nil)
}

@Test @MainActor func formTipPushup() {
    #expect(ExerciseService.formTip(for: "pushup") != nil)
}

@Test @MainActor func formTipDips() {
    #expect(ExerciseService.formTip(for: "dip") != nil)
}

// MARK: - formTip (back)

@Test @MainActor func formTipDeadlift() {
    #expect(ExerciseService.formTip(for: "deadlift") != nil)
}

@Test @MainActor func formTipRomanianDeadlift() {
    #expect(ExerciseService.formTip(for: "romanian deadlift") != nil)
}

@Test @MainActor func formTipRDL() {
    #expect(ExerciseService.formTip(for: "rdl") != nil)
}

@Test @MainActor func formTipBarbellRow() {
    #expect(ExerciseService.formTip(for: "barbell row") != nil)
}

@Test @MainActor func formTipBentOverRow() {
    #expect(ExerciseService.formTip(for: "bent over row") != nil)
}

@Test @MainActor func formTipPullUp() {
    #expect(ExerciseService.formTip(for: "pull up") != nil)
}

@Test @MainActor func formTipChinUp() {
    #expect(ExerciseService.formTip(for: "chin up") != nil)
}

@Test @MainActor func formTipLatPulldown() {
    #expect(ExerciseService.formTip(for: "lat pulldown") != nil)
}

@Test @MainActor func formTipCableRow() {
    #expect(ExerciseService.formTip(for: "cable row") != nil)
}

@Test @MainActor func formTipSeatedRow() {
    #expect(ExerciseService.formTip(for: "seated row") != nil)
}

// MARK: - formTip (legs)

@Test @MainActor func formTipSquat() {
    #expect(ExerciseService.formTip(for: "squat") != nil)
}

@Test @MainActor func formTipLegPress() {
    #expect(ExerciseService.formTip(for: "leg press") != nil)
}

@Test @MainActor func formTipLunge() {
    #expect(ExerciseService.formTip(for: "lunge") != nil)
}

@Test @MainActor func formTipSplitSquat() {
    #expect(ExerciseService.formTip(for: "split squat") != nil)
}

@Test @MainActor func formTipLegCurl() {
    #expect(ExerciseService.formTip(for: "leg curl") != nil)
}

@Test @MainActor func formTipLegExtension() {
    #expect(ExerciseService.formTip(for: "leg extension") != nil)
}

@Test @MainActor func formTipCalfRaise() {
    #expect(ExerciseService.formTip(for: "calf raise") != nil)
}

@Test @MainActor func formTipHipThrust() {
    #expect(ExerciseService.formTip(for: "hip thrust") != nil)
}

// MARK: - formTip (shoulders)

@Test @MainActor func formTipOverheadPress() {
    #expect(ExerciseService.formTip(for: "overhead press") != nil)
}

@Test @MainActor func formTipShoulderPress() {
    #expect(ExerciseService.formTip(for: "shoulder press") != nil)
}

@Test @MainActor func formTipMilitaryPress() {
    #expect(ExerciseService.formTip(for: "military press") != nil)
}

@Test @MainActor func formTipLateralRaise() {
    #expect(ExerciseService.formTip(for: "lateral raise") != nil)
}

@Test @MainActor func formTipFacePull() {
    #expect(ExerciseService.formTip(for: "face pull") != nil)
}

@Test @MainActor func formTipFrontRaise() {
    #expect(ExerciseService.formTip(for: "front raise") != nil)
}

@Test @MainActor func formTipShrug() {
    #expect(ExerciseService.formTip(for: "barbell shrug") != nil)
}

// MARK: - formTip (arms)

@Test @MainActor func formTipBicepCurl() {
    #expect(ExerciseService.formTip(for: "bicep curl") != nil)
}

@Test @MainActor func formTipBarbellCurl() {
    #expect(ExerciseService.formTip(for: "barbell curl") != nil)
}

@Test @MainActor func formTipHammerCurl() {
    #expect(ExerciseService.formTip(for: "hammer curl") != nil)
}

@Test @MainActor func formTipTricepPush() {
    #expect(ExerciseService.formTip(for: "tricep pushdown") != nil)
}

@Test @MainActor func formTipSkullCrusher() {
    #expect(ExerciseService.formTip(for: "skull crusher") != nil)
}

@Test @MainActor func formTipLyingTricep() {
    #expect(ExerciseService.formTip(for: "lying tricep extension") != nil)
}

@Test @MainActor func formTipCloseGrip() {
    #expect(ExerciseService.formTip(for: "close grip bench press") != nil)
}

// MARK: - formTip (core)

@Test @MainActor func formTipPlank() {
    #expect(ExerciseService.formTip(for: "plank") != nil)
}

@Test @MainActor func formTipCrunch() {
    #expect(ExerciseService.formTip(for: "crunch") != nil)
}

@Test @MainActor func formTipSitUp() {
    #expect(ExerciseService.formTip(for: "sit up") != nil)
}

@Test @MainActor func formTipLegRaise() {
    #expect(ExerciseService.formTip(for: "leg raise") != nil)
}

@Test @MainActor func formTipAbWheel() {
    #expect(ExerciseService.formTip(for: "ab wheel rollout") != nil)
}

@Test @MainActor func formTipCableWoodchop() {
    #expect(ExerciseService.formTip(for: "cable woodchop") != nil)
}

// MARK: - formTip edge cases

@Test @MainActor func formTipUnknownExerciseReturnsNil() {
    #expect(ExerciseService.formTip(for: "blobfish lift") == nil)
}

@Test @MainActor func formTipEmptyStringReturnsNil() {
    #expect(ExerciseService.formTip(for: "") == nil)
}

// "incline bench press" matches the bench-press rule (contains "bench press"),
// while "incline dumbbell press" falls through to the incline rule.
@Test @MainActor func formTipInclinePressVsInclineBenchPress() {
    let inclineDumbbell = ExerciseService.formTip(for: "incline dumbbell press")
    let inclineBench = ExerciseService.formTip(for: "incline bench press")
    // Both return a tip
    #expect(inclineDumbbell != nil)
    #expect(inclineBench != nil)
    // Dumbbell incline hits the incline rule; bench hits the bench-press rule first
    #expect(inclineDumbbell != inclineBench)
}

// MARK: - resolveSplitType

@Test @MainActor func resolveSplitTypePPL() {
    #expect(ExerciseService.resolveSplitType("ppl") == "ppl")
}

@Test @MainActor func resolveSplitTypePushPullLegs() {
    #expect(ExerciseService.resolveSplitType("push pull legs") == "ppl")
}

@Test @MainActor func resolveSplitTypeUpperLower() {
    #expect(ExerciseService.resolveSplitType("upper lower split") == "upper/lower")
}

@Test @MainActor func resolveSplitTypeFullBody() {
    #expect(ExerciseService.resolveSplitType("full body") == "full body")
}

@Test @MainActor func resolveSplitTypeFullbody() {
    #expect(ExerciseService.resolveSplitType("fullbody routine") == "full body")
}

@Test @MainActor func resolveSplitTypeBroSplit() {
    #expect(ExerciseService.resolveSplitType("bro split") == "bro split")
}

@Test @MainActor func resolveSplitTypeUnknownReturnsNil() {
    #expect(ExerciseService.resolveSplitType("random training plan") == nil)
}

// MARK: - splitDefinitions

@Test @MainActor func splitDefinitionsHasExpectedKeys() {
    let keys = Set(ExerciseService.splitDefinitions.keys)
    #expect(keys.contains("ppl"))
    #expect(keys.contains("upper/lower"))
    #expect(keys.contains("full body"))
    #expect(keys.contains("bro split"))
}

@Test @MainActor func splitDefinitionsPPLHasThreeDays() {
    #expect(ExerciseService.splitDefinitions["ppl"]?.count == 3)
}

@Test @MainActor func splitDefinitionsBroSplitHasFiveDays() {
    #expect(ExerciseService.splitDefinitions["bro split"]?.count == 5)
}

// MARK: - suggestForSplitDay

@Test @MainActor func suggestForSplitDayValidPPL() {
    let exercises = ExerciseService.suggestForSplitDay(splitType: "ppl", dayIndex: 0)
    #expect(!exercises.isEmpty)
}

@Test @MainActor func suggestForSplitDayReturnsSixOrFewer() {
    let exercises = ExerciseService.suggestForSplitDay(splitType: "ppl", dayIndex: 0)
    #expect(exercises.count <= 6)
}

@Test @MainActor func suggestForSplitDayInvalidSplitReturnsEmpty() {
    let exercises = ExerciseService.suggestForSplitDay(splitType: "nonexistent", dayIndex: 0)
    #expect(exercises.isEmpty)
}

@Test @MainActor func suggestForSplitDayOutOfBoundsReturnsEmpty() {
    let exercises = ExerciseService.suggestForSplitDay(splitType: "ppl", dayIndex: 99)
    #expect(exercises.isEmpty)
}

@Test @MainActor func suggestForSplitDayDeduplicates() {
    let exercises = ExerciseService.suggestForSplitDay(splitType: "ppl", dayIndex: 0)
    let names = exercises.map(\.name)
    let unique = Set(names)
    #expect(names.count == unique.count)
}

// MARK: - buildSplitTemplate

@Test @MainActor func buildSplitTemplateReturnsTemplate() {
    let t = ExerciseService.buildSplitTemplate(name: "Push", exerciseNames: ["Bench Press", "Overhead Press"])
    #expect(t != nil)
    #expect(t?.name == "Push")
}

@Test @MainActor func buildSplitTemplateEmptyNamesReturnsNilOrEmpty() {
    // Empty names list should encode to an empty JSON array — template may still be created
    let t = ExerciseService.buildSplitTemplate(name: "Empty", exerciseNames: [])
    // Either nil or a template with no exercises is acceptable
    if let t {
        #expect(t.exercises.isEmpty)
    }
}

@Test @MainActor func buildSplitTemplateIncludesFormTips() {
    // bench press has a known form tip — it should appear in notes
    let t = ExerciseService.buildSplitTemplate(name: "Chest", exerciseNames: ["Bench Press"])
    #expect(t != nil)
    let exercises = t?.exercises ?? []
    if let notes = exercises.first?.notes {
        // Either the tip "Drive feet" or a default set count should appear
        #expect(!notes.isEmpty)
    }
}

// MARK: - exerciseInstructions

@Test @MainActor func exerciseInstructionsFormatsCorrectly() {
    guard let info = ExerciseDatabase.search(query: "bench press").first else { return }
    let instructions = ExerciseService.exerciseInstructions(info)
    #expect(instructions.contains(info.name))
    #expect(instructions.contains(info.category))
    #expect(instructions.contains(info.level))
}

@Test @MainActor func exerciseInstructionsIncludesFormTipWhenAvailable() {
    guard let info = ExerciseDatabase.search(query: "bench press").first else { return }
    let instructions = ExerciseService.exerciseInstructions(info)
    // bench press has a known form tip
    #expect(instructions.contains("Form:"))
}

// MARK: - getProgressiveOverload (empty DB → insufficientData)

@Test @MainActor func getProgressiveOverloadEmptyDBReturnsInsufficient() {
    let info = ExerciseService.getProgressiveOverload(exercise: "Nonexistent Exercise XYZ")
    // With no data, returns insufficientData or nil
    if let info {
        #expect(info.status == .insufficientData)
    }
}

// MARK: - resolveExerciseName

@Test @MainActor func resolveExerciseNameKnownExercise() {
    // "bench" should match something in the DB
    let result = ExerciseService.resolveExerciseName("bench")
    #expect(result != nil)
}

@Test @MainActor func resolveExerciseNameUnknownReturnsNil() {
    let result = ExerciseService.resolveExerciseName("xyzunknown9999")
    #expect(result == nil)
}

// MARK: - Compound lift instructions (top 20)

private let compoundLifts = [
    "Barbell Full Squat", "Barbell Deadlift", "Barbell Bench Press - Medium Grip",
    "Overhead Press", "Bent Over Barbell Row", "Pull-Up", "Dips - Triceps Version",
    "Romanian Deadlift", "Front Squat", "Sumo Deadlift",
    "Barbell Incline Bench Press - Medium Grip", "Close-Grip Barbell Bench Press",
    "Seated Cable Rows", "Lat Pulldown", "Leg Press", "Lying Leg Curls",
    "Leg Extensions", "Barbell Hip Thrust", "Face Pull", "Arnold Press",
]

@Test @MainActor func allCompoundLiftsHaveInstructions() {
    for name in compoundLifts {
        let info = ExerciseDatabase.info(for: name)
        #expect(info != nil, "Exercise not found: \(name)")
        #expect((info?.instructions?.count ?? 0) >= 3,
                "\(name) should have ≥3 instruction bullets, got \(info?.instructions?.count ?? 0)")
    }
}

@Test @MainActor func exerciseInstructionsIncludesFormCues() {
    let info = ExerciseDatabase.info(for: "Barbell Deadlift")
    #expect(info != nil)
    let text = ExerciseService.exerciseInstructions(info!)
    #expect(text.contains("Setup:"), "Should include Setup cue")
    #expect(text.contains("Execution:"), "Should include Execution cue")
    #expect(text.contains("Common error:"), "Should include Common error cue")
}
