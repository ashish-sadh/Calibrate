import XCTest
@testable import DriftCore

/// Tier-0: the pure decode/validation path of the cloud workout extractor
/// (#969). The cloud CALL is not exercised here (that's Tier-3 eval); these
/// lock the JSON→[FMExerciseEntry] mapping + bounds gating that stops a bad
/// cloud reply from injecting junk exercises.
///
/// Moved down with the logger itself when Android was wired onto the same cloud
/// path (#1064) — nothing here needs the simulator.
final class NebiusExerciseLoggerTests: XCTestCase {

    func testSingleEntryDecodes() {
        let raw = #"{"entries":[{"exerciseName":"back extension","sets":3,"reps":10,"weight":null,"durationMinutes":null,"category":"strength"}]}"#
        let entries = NebiusExerciseLogger.decode(raw)
        XCTAssertEqual(entries?.count, 1)
        XCTAssertEqual(entries?.first?.exerciseName, "back extension")
        XCTAssertEqual(entries?.first?.sets, 3)
        XCTAssertEqual(entries?.first?.reps, 10)
        XCTAssertNil(entries?.first?.weight)
        XCTAssertEqual(entries?.first?.category, .strength)
    }

    func testSingleUtteranceStaysSingle() {
        // The exact #969 input must NOT expand into a full workout.
        let raw = #"{"entries":[{"exerciseName":"back extension","sets":3,"reps":10,"weight":null,"durationMinutes":null,"category":"strength"}]}"#
        XCTAssertEqual(NebiusExerciseLogger.decode(raw)?.count, 1)
    }

    func testEmptyEntriesIsNil() {
        XCTAssertNil(NebiusExerciseLogger.decode(#"{"entries":[]}"#))
    }

    func testMultipleValidEntriesAllReturned() {
        let raw = #"{"entries":[{"exerciseName":"squat","sets":3,"reps":5,"weight":225,"durationMinutes":null,"category":"strength"},{"exerciseName":"running","sets":null,"reps":null,"weight":null,"durationMinutes":30,"category":"cardio"}]}"#
        let entries = NebiusExerciseLogger.decode(raw)
        XCTAssertEqual(entries?.count, 2)
        XCTAssertEqual(entries?.last?.category, .cardio)
        XCTAssertEqual(entries?.last?.durationMinutes, 30)
    }

    func testOutOfRangeEntryDropped() {
        // sets=99 exceeds ExerciseTranscriptBounds.setsRange (1...20) → dropped,
        // valid sibling kept.
        let raw = #"{"entries":[{"exerciseName":"curl","sets":99,"reps":10,"weight":20,"durationMinutes":null,"category":"strength"},{"exerciseName":"bench press","sets":3,"reps":8,"weight":135,"durationMinutes":null,"category":"strength"}]}"#
        let entries = NebiusExerciseLogger.decode(raw)
        XCTAssertEqual(entries?.count, 1)
        XCTAssertEqual(entries?.first?.exerciseName, "bench press")
    }

    func testUnnamedEntryDropped() {
        let raw = #"{"entries":[{"exerciseName":"   ","sets":3,"reps":10,"weight":null,"durationMinutes":null,"category":"strength"}]}"#
        XCTAssertNil(NebiusExerciseLogger.decode(raw))
    }

    func testNonJSONIsNil() {
        XCTAssertNil(NebiusExerciseLogger.decode("I could not parse that workout, sorry!"))
    }

    func testJSONWithProseWrapperStillDecodes() {
        let raw = "Sure! Here you go:\n{\"entries\":[{\"exerciseName\":\"deadlift\",\"sets\":5,\"reps\":5,\"weight\":176,\"durationMinutes\":null,\"category\":\"strength\"}]}\nHope that helps."
        XCTAssertEqual(NebiusExerciseLogger.decode(raw)?.first?.exerciseName, "deadlift")
    }

    func testUnknownCategoryFallsBackToStrength() {
        let raw = #"{"entries":[{"exerciseName":"thruster","sets":3,"reps":12,"weight":95,"durationMinutes":null,"category":"crossfit"}]}"#
        XCTAssertEqual(NebiusExerciseLogger.decode(raw)?.first?.category, .strength)
    }

    func testEntryCountCappedAtMax() {
        // 15 valid entries → capped at ExerciseTranscriptBounds.maxEntries (12).
        let items = (0..<15).map {
            #"{"exerciseName":"ex\#($0)","sets":3,"reps":10,"weight":null,"durationMinutes":null,"category":"strength"}"#
        }.joined(separator: ",")
        let entries = NebiusExerciseLogger.decode("{\"entries\":[\(items)]}")
        XCTAssertEqual(entries?.count, ExerciseTranscriptBounds.maxEntries)
    }
}
