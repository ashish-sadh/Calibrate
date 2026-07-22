import XCTest
@testable import DriftCore

/// Tier-0: pure name-canonicalisation + date inference for scanned workouts.
final class ExerciseNameNormalizerTests: XCTestCase {

    private var today: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2026, month: 7, day: 21))!
    }
    private func ymd(_ d: Date?) -> String? { d.map { DateFormatters.dateOnly.string(from: $0) } }

    func testExpandsGymShorthand() {
        XCTAssertEqual(ExerciseNameNormalizer.canonical("Incline DB press"), "Incline Dumbbell Press")
        XCTAssertEqual(ExerciseNameNormalizer.canonical("BB back squat"), "Barbell Back Squat")
        XCTAssertEqual(ExerciseNameNormalizer.canonical("RDL"), "Romanian Deadlift")
        XCTAssertEqual(ExerciseNameNormalizer.canonical("ohp"), "Overhead Press")
    }

    func testDropsBodyweightAndSupersetMarkers() {
        // "BW pushups" → the BW marker drops, movement stays.
        XCTAssertEqual(ExerciseNameNormalizer.canonical("BW pushups"), "Pushups")
        XCTAssertEqual(ExerciseNameNormalizer.canonical("SS paloff press"), "Paloff Press")
    }

    func testEmptyAndMarkerOnly() {
        XCTAssertEqual(ExerciseNameNormalizer.canonical("   "), "")
        XCTAssertEqual(ExerciseNameNormalizer.canonical("BW"), "")
    }

    func testPreservesShortAcronyms() {
        XCTAssertEqual(ExerciseNameNormalizer.canonical("EZ bar curl"), "EZ Bar Curl")
    }

    func testParsesISODate() {
        XCTAssertEqual(ymd(ExerciseNameNormalizer.parseDate("2026-03-12", referenceDate: today)), "2026-03-12")
    }

    func testYearlessDateUsesCurrentYearWhenPast() {
        XCTAssertEqual(ymd(ExerciseNameNormalizer.parseDate("3/12", referenceDate: today)), "2026-03-12")
    }

    func testYearlessFutureDateRollsBackAYear() {
        // 12/25 is after 2026-07-21 → previous year.
        XCTAssertEqual(ymd(ExerciseNameNormalizer.parseDate("12/25", referenceDate: today)), "2025-12-25")
    }

    func testTwoDigitYear() {
        XCTAssertEqual(ymd(ExerciseNameNormalizer.parseDate("3/26/26", referenceDate: today)), "2026-03-26")
    }

    func testGarbageDateIsNil() {
        XCTAssertNil(ExerciseNameNormalizer.parseDate("sometime", referenceDate: today))
        XCTAssertNil(ExerciseNameNormalizer.parseDate("null", referenceDate: today))
    }
}
