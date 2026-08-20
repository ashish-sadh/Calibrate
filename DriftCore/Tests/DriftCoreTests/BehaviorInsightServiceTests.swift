import XCTest
@testable import DriftCore

@MainActor
final class BehaviorInsightServiceTests: XCTestCase {

    // MARK: - proteinAdherenceAlertVariant

    func testFiresOnConsecutiveStreak3() {
        let result = BehaviorInsightService.proteinAdherenceAlertVariant(
            missedDays: 3, loggedDays: 5, consecutiveStreak: 3,
            avgProtein: 55, proteinTarget: 120)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.dismissKey, "protein_streak")
        XCTAssertFalse(result?.isPositive ?? true)
    }

    func testFiresOnFourOfSeven() {
        let result = BehaviorInsightService.proteinAdherenceAlertVariant(
            missedDays: 4, loggedDays: 7, consecutiveStreak: 1,
            avgProtein: 70, proteinTarget: 120)
        XCTAssertNotNil(result)
    }

    func testSilentBelow3Consecutive() {
        let result = BehaviorInsightService.proteinAdherenceAlertVariant(
            missedDays: 2, loggedDays: 5, consecutiveStreak: 2,
            avgProtein: 100, proteinTarget: 120)
        XCTAssertNil(result)
    }

    func testSilentBelow4OfSeven() {
        let result = BehaviorInsightService.proteinAdherenceAlertVariant(
            missedDays: 3, loggedDays: 7, consecutiveStreak: 0,
            avgProtein: 100, proteinTarget: 120)
        XCTAssertNil(result)
    }

    func testMessageContainsAvgAndTarget() {
        let result = BehaviorInsightService.proteinAdherenceAlertVariant(
            missedDays: 5, loggedDays: 7, consecutiveStreak: 0,
            avgProtein: 63, proteinTarget: 140)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.detail.contains("63g"), "Should show avg protein consumed")
        XCTAssertTrue(result!.detail.contains("140g"), "Should show protein target")
    }

    func testMessageDescribesConsecutiveWhenStreakHigher() {
        let result = BehaviorInsightService.proteinAdherenceAlertVariant(
            missedDays: 4, loggedDays: 7, consecutiveStreak: 4,
            avgProtein: 50, proteinTarget: 100)
        XCTAssertTrue(result!.detail.contains("4 days in a row"))
    }

    func testMessageDescribesFractionWhenNoStreak() {
        let result = BehaviorInsightService.proteinAdherenceAlertVariant(
            missedDays: 5, loggedDays: 7, consecutiveStreak: 1,
            avgProtein: 50, proteinTarget: 100)
        XCTAssertTrue(result!.detail.contains("5 of the last 7"))
    }

    // MARK: - glucoseSpikeAlertVariant

    func testGlucoseSpikeAlertFires() {
        let result = BehaviorInsightService.glucoseSpikeAlertVariant(spikeDays: 3, dataDays: 5)
        XCTAssertNotNil(result)
    }

    func testGlucoseSpikeAlertSilentInsufficientData() {
        let result = BehaviorInsightService.glucoseSpikeAlertVariant(spikeDays: 3, dataDays: 2)
        XCTAssertNil(result)
    }

    // MARK: - sleepVsCaloriesInsight
    //
    // Hermetic by construction: `nutrition` is injected, so these assert the
    // guard rules themselves. The iOS copies drove `computeInsights(sleepHistory:)`
    // against the live database and asserted "no insight" purely because the DB
    // happened to be empty on a rolling -100d window; on 2026-08-19 that window
    // slid into a seeded range and the case flipped without a line of code changing.

    /// Builds `count` alternating good(8h)/poor(5h) nights ending `startDaysAgo` back.
    private func nights(count: Int, startDaysAgo: Int = 1) -> [(date: Date, hours: Double)] {
        (0..<count).map { i in
            (date: Calendar.current.date(byAdding: .day, value: -(i + startDaysAgo), to: Date())!,
             hours: i % 2 == 0 ? 8.0 : 5.0)
        }
    }

    private func fed(_ nights: [(date: Date, hours: Double)], calories: (Double) -> Double)
        -> [String: DailyNutrition] {
        var out: [String: DailyNutrition] = [:]
        for n in nights {
            out[DateFormatters.dateOnly.string(from: n.date)] =
                DailyNutrition(calories: calories(n.hours), proteinG: 100, carbsG: 200, fatG: 60, fiberG: 25)
        }
        return out
    }

    func testSleepInsightRequiresMin7Nights() {
        let six = nights(count: 6)
        XCTAssertNil(BehaviorInsightService.sleepVsCaloriesInsight(
            sleepHistory: six, nutrition: fed(six) { $0 >= 7 ? 1800 : 2400 }),
            "< 7 nights should produce no sleep insight even with full calorie data")
    }

    func testSleepInsightEmptyHistoryProducesNoInsight() {
        XCTAssertNil(BehaviorInsightService.sleepVsCaloriesInsight(
            sleepHistory: [], nutrition: [:]))
    }

    func testSleepInsightWith7NightsButNoCalorieDataProducesNoInsight() {
        XCTAssertNil(BehaviorInsightService.sleepVsCaloriesInsight(
            sleepHistory: nights(count: 7), nutrition: [:]),
            "no calorie data should produce no insight even with enough nights")
    }

    func testSleepInsightIgnoresDaysUnder200Calories() {
        let seven = nights(count: 7)
        XCTAssertNil(BehaviorInsightService.sleepVsCaloriesInsight(
            sleepHistory: seven, nutrition: fed(seven) { _ in 150 }),
            "days logged under 200cal are skipped, so the pair counts never fill")
    }

    func testSleepInsightAllGoodSleepProducesNoInsight() {
        let allGood = (0..<7).map { i in
            (date: Calendar.current.date(byAdding: .day, value: -(i + 1), to: Date())!, hours: 8.0)
        }
        XCTAssertNil(BehaviorInsightService.sleepVsCaloriesInsight(
            sleepHistory: allGood, nutrition: fed(allGood) { _ in 2000 }),
            "no poor-sleep nights means nothing to compare against")
    }

    func testSleepInsightNegligibleDifferenceProducesNoInsight() {
        let seven = nights(count: 7)
        XCTAssertNil(BehaviorInsightService.sleepVsCaloriesInsight(
            sleepHistory: seven, nutrition: fed(seven) { $0 >= 7 ? 2000 : 2020 }),
            "a 20cal gap is noise, not a finding")
    }

    /// The positive case — without it the negatives above could all pass vacuously.
    func testSleepInsightFiresWhenPoorSleepMeansMoreCalories() {
        let seven = nights(count: 7)
        let insight = BehaviorInsightService.sleepVsCaloriesInsight(
            sleepHistory: seven, nutrition: fed(seven) { $0 >= 7 ? 1800 : 2400 })
        XCTAssertNotNil(insight)
        XCTAssertEqual(insight?.icon, "moon.zzz.fill")
        XCTAssertFalse(insight?.isPositive ?? true, "eating more after poor sleep is not a win")
        XCTAssertTrue(insight?.detail.contains("600") ?? false,
                      "detail should name the real gap (2400-1800), got: \(insight?.detail ?? "nil")")
    }

    func testSleepInsightAllPoorSleepProducesNoInsight() {
        let allPoor = (0..<7).map { i in
            (date: Calendar.current.date(byAdding: .day, value: -(i + 1), to: Date())!, hours: 5.0)
        }
        XCTAssertNil(BehaviorInsightService.sleepVsCaloriesInsight(
            sleepHistory: allPoor, nutrition: fed(allPoor) { _ in 2400 }),
            "no good-sleep nights means nothing to compare against")
    }

    /// 6.0h is the dead zone: not good (>= 7) and not poor (< 6), so eight such
    /// nights fill neither bucket.
    func testSleepInsightExactlySixHoursIsNeitherGoodNorPoor() {
        let boundary = (0..<8).map { i in
            (date: Calendar.current.date(byAdding: .day, value: -(i + 1), to: Date())!, hours: 6.0)
        }
        XCTAssertNil(BehaviorInsightService.sleepVsCaloriesInsight(
            sleepHistory: boundary, nutrition: fed(boundary) { _ in 2200 }))
    }
}
