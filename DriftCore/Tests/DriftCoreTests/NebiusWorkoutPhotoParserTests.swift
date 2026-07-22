import XCTest
@testable import DriftCore

/// Tier-0: the pure decode/mapping path of the workout PHOTO/PDF scanner. The
/// cloud vision CALL is not exercised here (that's runtime); these lock the
/// JSON → programs/sessions mapping, per-set expansion, bounds gating,
/// abbreviation expansion, and year-less date inference.
final class NebiusWorkoutPhotoParserTests: XCTestCase {

    // A fixed "today" so year-less date inference is deterministic.
    private var referenceDate: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2026, month: 7, day: 21))!
    }

    private func ymd(_ date: Date?) -> String? {
        guard let date else { return nil }
        return DateFormatters.dateOnly.string(from: date)
    }

    // MARK: decode

    func testDecodesTemplateOnly() {
        let raw = #"""
        {"templates":[{"name":"Push Day","exercises":[
          {"name":"Incline DB press","sets":3,"repsText":"10-12","restSeconds":120,"isWarmup":false,"notes":"30 degree bench"},
          {"name":"Banded Shoulder Rotations","sets":2,"repsText":"10","restSeconds":null,"isWarmup":true,"notes":null}
        ]}],"sessions":[]}
        """#
        let result = NebiusWorkoutPhotoParser.decode(raw, referenceDate: referenceDate)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.templates.count, 1)
        XCTAssertTrue(result?.sessions.isEmpty ?? false)
        let ex = result!.templates[0].exercises
        XCTAssertEqual(ex[0].name, "Incline Dumbbell Press")   // DB expanded
        XCTAssertEqual(ex[0].sets, 3)
        XCTAssertEqual(ex[0].restSeconds, 120)
        XCTAssertFalse(ex[0].isWarmup)
        XCTAssertTrue(ex[1].isWarmup)
    }

    func testDecodesSessionWithPerSetWeights() {
        // The user's notebook line: 45×10 / 60×15 / 70×8 → 3 distinct sets.
        let raw = #"""
        {"templates":[],"sessions":[{"date":"3/12","name":"Chest","exercises":[
          {"name":"Incline DB press","isDuration":false,"durationMinutes":null,"sets":[
            {"reps":10,"weightLbs":45,"isWarmup":false},
            {"reps":15,"weightLbs":60,"isWarmup":false},
            {"reps":8,"weightLbs":70,"isWarmup":false}
          ]}
        ]}]}
        """#
        let result = NebiusWorkoutPhotoParser.decode(raw, referenceDate: referenceDate)
        XCTAssertEqual(result?.sessions.count, 1)
        let sets = result!.sessions[0].exercises[0].sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets[0].weightLbs, 45)
        XCTAssertEqual(sets[1].reps, 15)
        XCTAssertEqual(sets[2].weightLbs, 70)
        // "3/12" with no year, before today 2026-07-21 → this year.
        XCTAssertEqual(ymd(result?.sessions[0].date), "2026-03-12")
    }

    func testDecodesBothTemplateAndSessionsOnOnePage() {
        let raw = #"""
        {"templates":[{"name":"Program","exercises":[{"name":"Pushups","sets":3,"repsText":"20","restSeconds":120,"isWarmup":false,"notes":null}]}],
         "sessions":[{"date":"2026-04-30","name":null,"exercises":[{"name":"Pushups","isDuration":false,"sets":[{"reps":25,"weightLbs":null,"isWarmup":false}]}]}]}
        """#
        let result = NebiusWorkoutPhotoParser.decode(raw, referenceDate: referenceDate)
        XCTAssertEqual(result?.templates.count, 1)
        XCTAssertEqual(result?.sessions.count, 1)
        XCTAssertEqual(result?.sessions[0].name, "Scanned Workout")  // null → default
        XCTAssertEqual(ymd(result?.sessions[0].date), "2026-04-30")
    }

    func testDurationExerciseKeepsMinutes() {
        let raw = #"""
        {"templates":[],"sessions":[{"date":null,"name":"Cardio","exercises":[
          {"name":"Yoga ball pike","isDuration":true,"durationMinutes":15,"sets":[]}
        ]}]}
        """#
        let result = NebiusWorkoutPhotoParser.decode(raw, referenceDate: referenceDate)
        let ex = result!.sessions[0].exercises[0]
        XCTAssertTrue(ex.isDuration)
        XCTAssertEqual(ex.durationMinutes, 15)
        XCTAssertNil(result?.sessions[0].date)
    }

    func testEmptyPayloadIsNonNilButEmpty() {
        let result = NebiusWorkoutPhotoParser.decode(#"{"templates":[],"sessions":[]}"#, referenceDate: referenceDate)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.isEmpty ?? false)
    }

    func testNonJSONIsNil() {
        XCTAssertNil(NebiusWorkoutPhotoParser.decode("that's not a workout page", referenceDate: referenceDate))
    }

    func testProseWrappedJSONStillDecodes() {
        let raw = "Here you go:\n{\"templates\":[],\"sessions\":[{\"date\":null,\"name\":\"W\",\"exercises\":[{\"name\":\"squat\",\"isDuration\":false,\"sets\":[{\"reps\":5,\"weightLbs\":225,\"isWarmup\":false}]}]}]}\nDone."
        XCTAssertEqual(NebiusWorkoutPhotoParser.decode(raw, referenceDate: referenceDate)?.sessions.count, 1)
    }

    func testOutOfRangeSetDropped() {
        // reps 9999 clamps to max; weight 5000 (>1100) drops to nil but reps keep the set.
        let raw = #"""
        {"templates":[],"sessions":[{"date":null,"name":"W","exercises":[
          {"name":"curl","isDuration":false,"sets":[{"reps":9999,"weightLbs":5000,"isWarmup":false}]}
        ]}]}
        """#
        let set = NebiusWorkoutPhotoParser.decode(raw, referenceDate: referenceDate)!.sessions[0].exercises[0].sets[0]
        XCTAssertEqual(set.reps, ExerciseTranscriptBounds.repsRange.upperBound)
        XCTAssertNil(set.weightLbs)
    }

    func testInfoFreeSetDropsExercise() {
        // A set with neither reps nor weight carries nothing → exercise dropped → session dropped.
        let raw = #"""
        {"templates":[],"sessions":[{"date":null,"name":"W","exercises":[
          {"name":"mystery","isDuration":false,"sets":[{"reps":null,"weightLbs":null,"isWarmup":false}]}
        ]}]}
        """#
        let result = NebiusWorkoutPhotoParser.decode(raw, referenceDate: referenceDate)
        XCTAssertTrue(result?.sessions.isEmpty ?? false)
    }

    // MARK: request message (user note rider)

    func testRequestMessageWithoutNote() {
        let msg = NebiusWorkoutPhotoParser.requestMessage(userNote: nil)
        XCTAssertFalse(msg.contains("User note"))
    }

    func testRequestMessageAppendsNote() {
        let msg = NebiusWorkoutPhotoParser.requestMessage(userNote: "weights are in kg")
        XCTAssertTrue(msg.contains("User note about this image: weights are in kg"))
    }

    func testRequestMessageIgnoresBlankNote() {
        let msg = NebiusWorkoutPhotoParser.requestMessage(userNote: "   \n ")
        XCTAssertFalse(msg.contains("User note"))
    }

    // MARK: template → json mapping

    func testTemplateExercisesJSONFoldsRepsIntoNotes() {
        let t = ScannedTemplate(name: "T", exercises: [
            ScannedTemplateExercise(name: "Bench Press", sets: 3, repsText: "8-12", restSeconds: 90,
                                    isWarmup: false, notes: "pause at chest")
        ])
        let mapped = t.templateExercises
        XCTAssertEqual(mapped[0].notes, "8-12 reps · pause at chest")
        // JSON round-trips back through the model's decoder.
        let decoded = try? JSONDecoder().decode([WorkoutTemplate.TemplateExercise].self,
                                                from: Data(t.exercisesJSON.utf8))
        XCTAssertEqual(decoded?.first?.sets, 3)
        XCTAssertEqual(decoded?.first?.name, "Bench Press")
    }

    // MARK: exercise-library grounding

    func testUnknownExerciseNamesFiltersDedupsAndTrims() {
        let known: Set<String> = ["pushups", "incline dumbbell press"]
        let result = WorkoutService.unknownExerciseNames(
            ["  Pushups ", "Yoga Ball Pike", "yoga ball pike", "INCLINE DUMBBELL PRESS", "", "Woodchopper"],
            known: known)
        // Known names drop (case-insensitive), dupes collapse, order preserved.
        XCTAssertEqual(result, ["Yoga Ball Pike", "Woodchopper"])
    }

    func testGroundedExerciseNamePassesUnknownThrough() {
        XCTAssertEqual(WorkoutService.groundedExerciseName("  Zzz Nonexistent Movement  "),
                       "Zzz Nonexistent Movement")
    }

    func testGroundedExerciseNameUsesCatalogSpelling() {
        // Whatever match() resolves for a confident query is what rows must carry
        // — grounding and matching may never disagree, or scanned rows would
        // miss their library entry (tracking type, poses).
        if let matched = ExerciseDatabase.match(name: "pushups") {
            XCTAssertEqual(WorkoutService.groundedExerciseName("pushups"), matched.name)
        } else {
            XCTFail("catalog no longer matches 'pushups' — grounding baseline broken")
        }
    }

    // MARK: buildScannedSessionSets

    func testBuildSessionSetsExpandsPerSet() {
        let ex = [ScannedSessionExercise(name: "Squat", isDuration: false, sets: [
            ScannedSet(reps: 5, weightLbs: 135), ScannedSet(reps: 5, weightLbs: 185)
        ])]
        let rows = WorkoutService.buildScannedSessionSets(workoutId: 7, exercises: ex)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].setOrder, 1)
        XCTAssertEqual(rows[0].weightLbs, 135)
        XCTAssertEqual(rows[1].setOrder, 2)
        XCTAssertEqual(rows[1].weightLbs, 185)
        XCTAssertEqual(rows[0].exerciseOrder, 0)
    }

    func testBuildSessionSetsDurationRow() {
        let ex = [ScannedSessionExercise(name: "Plank", isDuration: true, sets: [], durationMinutes: 3)]
        let rows = WorkoutService.buildScannedSessionSets(workoutId: 1, exercises: ex)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].durationSec, 180)
        XCTAssertNil(rows[0].reps)
    }

    func testBuildSessionSetsSkipsBlankName() {
        let ex = [ScannedSessionExercise(name: "  ", isDuration: false, sets: [ScannedSet(reps: 5)])]
        XCTAssertTrue(WorkoutService.buildScannedSessionSets(workoutId: 1, exercises: ex).isEmpty)
    }
}
