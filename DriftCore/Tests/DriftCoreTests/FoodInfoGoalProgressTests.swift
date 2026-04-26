import XCTest
@testable import DriftCore

/// Covers the pure formatter used by food_info when a macro goal is set.
/// Integration against WeightGoal.load() lives in FoodLoggingGoldSetTests + live eval.
final class FoodInfoGoalProgressTests: XCTestCase {

    func testUnderGoalShowsRemaining() {
        let line = FoodService.macroProgressLine(label: "Protein", currentG: 87, targetG: 120)
        XCTAssertEqual(line, "Protein: 87g / 120g goal — 72% (33g to go).")
    }

    func testExactlyAtGoalShowsReached() {
        let line = FoodService.macroProgressLine(label: "Protein", currentG: 120, targetG: 120)
        XCTAssertEqual(line, "Protein: 120g / 120g goal — 100% (target reached!).")
    }

    func testOverGoalShowsOverAmount() {
        let line = FoodService.macroProgressLine(label: "Carbs", currentG: 250, targetG: 200)
        XCTAssertEqual(line, "Carbs: 250g / 200g goal — 125% (50g over).")
    }

    func testZeroIntakeShowsZeroPercent() {
        let line = FoodService.macroProgressLine(label: "Fat", currentG: 0, targetG: 60)
        XCTAssertEqual(line, "Fat: 0g / 60g goal — 0% (60g to go).")
    }

    func testNoGoalFallsBackToBareCount() {
        let line = FoodService.macroProgressLine(label: "Protein", currentG: 87, targetG: 0)
        XCTAssertEqual(line, "Protein: 87g.")
    }

    func testNegativeCurrentClampedToZero() {
        let line = FoodService.macroProgressLine(label: "Protein", currentG: -5, targetG: 100)
        XCTAssertEqual(line, "Protein: 0g / 100g goal — 0% (100g to go).")
    }

    func testNegativeTargetTreatedAsMissing() {
        let line = FoodService.macroProgressLine(label: "Protein", currentG: 50, targetG: -10)
        XCTAssertEqual(line, "Protein: 50g.")
    }

    func testPercentageFloors() {
        // 99/120 = 82.5% → floors to 82% (Int truncation)
        let line = FoodService.macroProgressLine(label: "Protein", currentG: 99, targetG: 120)
        XCTAssertTrue(line.contains("82%"), "expected 82%, got: \(line)")
    }

    func testAllThreeMacrosShareShape() {
        let protein = FoodService.macroProgressLine(label: "Protein", currentG: 50, targetG: 100)
        let carbs = FoodService.macroProgressLine(label: "Carbs", currentG: 50, targetG: 100)
        let fat = FoodService.macroProgressLine(label: "Fat", currentG: 50, targetG: 100)
        XCTAssertTrue(protein.contains("50% (50g to go)"))
        XCTAssertTrue(carbs.contains("50% (50g to go)"))
        XCTAssertTrue(fat.contains("50% (50g to go)"))
    }

    func testCustomUnitRespected() {
        let line = FoodService.macroProgressLine(label: "Calories", currentG: 1500, targetG: 2000, unit: " cal")
        XCTAssertEqual(line, "Calories: 1500 cal / 2000 cal goal — 75% (500 cal to go).")
    }

    // MARK: - Calorie goal progress format (#441)

    func testCalorieGoalProgressUnder() {
        let line = FoodService.macroProgressLine(label: "Calories", currentG: 1400, targetG: 2000, unit: " cal")
        XCTAssertEqual(line, "Calories: 1400 cal / 2000 cal goal — 70% (600 cal to go).")
    }

    func testCalorieGoalProgressOver() {
        let line = FoodService.macroProgressLine(label: "Calories", currentG: 2200, targetG: 2000, unit: " cal")
        XCTAssertEqual(line, "Calories: 2200 cal / 2000 cal goal — 110% (200 cal over).")
    }

    func testCalorieGoalProgressExact() {
        let line = FoodService.macroProgressLine(label: "Calories", currentG: 2000, targetG: 2000, unit: " cal")
        XCTAssertEqual(line, "Calories: 2000 cal / 2000 cal goal — 100% (target reached!).")
    }

    // MARK: - WeightGoal.proteinGoal / calorieGoal (#440)

    func testWeightGoal_ProteinGoalRoundTrips() {
        var goal = WeightGoal(targetWeightKg: 75, monthsToAchieve: 6,
                              startDate: "2026-01-01", startWeightKg: 80)
        goal.proteinGoal = 150
        let data = try! JSONEncoder().encode(goal)
        let decoded = try! JSONDecoder().decode(WeightGoal.self, from: data)
        XCTAssertEqual(decoded.proteinGoal, 150)
    }

    func testWeightGoal_ProteinGoalNilByDefault() {
        let goal = WeightGoal(targetWeightKg: 75, monthsToAchieve: 6,
                              startDate: "2026-01-01", startWeightKg: 80)
        XCTAssertNil(goal.proteinGoal)
    }

    func testWeightGoal_CalorieGoalMirrorsOverride() {
        var goal = WeightGoal(targetWeightKg: 75, monthsToAchieve: 6,
                              startDate: "2026-01-01", startWeightKg: 80)
        goal.calorieGoal = 2000
        XCTAssertEqual(goal.calorieTargetOverride, 2000)
        goal.calorieTargetOverride = 1800
        XCTAssertEqual(goal.calorieGoal, 1800)
    }

    func testWeightGoal_BothGoalsIndependent() {
        var goal = WeightGoal(targetWeightKg: 75, monthsToAchieve: 6,
                              startDate: "2026-01-01", startWeightKg: 80)
        goal.calorieGoal = 2000
        goal.proteinGoal = 150
        XCTAssertEqual(goal.calorieGoal, 2000)
        XCTAssertEqual(goal.proteinGoal, 150)
        goal.proteinGoal = nil
        XCTAssertNil(goal.proteinGoal)
        XCTAssertEqual(goal.calorieGoal, 2000, "Clearing proteinGoal must not affect calorieGoal")
    }

    // MARK: - StaticOverrides protein goal routing (#440)

    @MainActor
    func testStaticOverrides_ProteinGoalPatternMatches() {
        let matchingQueries = [
            "set my protein target to 150g",
            "set protein target 120",
            "protein goal 180g",
            "my protein target is 160",
            "set protein goal to 200",
        ]
        for query in matchingQueries {
            let result = StaticOverrides.match(query.lowercased())
            XCTAssertNotNil(result, "Should match protein goal pattern: '\(query)'")
            if case .handler = result { /* pass */ }
            else { XCTFail("Protein goal '\(query)' should return .handler, got: \(String(describing: result))") }
        }
    }

    @MainActor
    func testStaticOverrides_ProteinGoalOutOfRangeRejected() {
        // Values outside 20–400 should not match the protein goal pattern
        let nonMatches = [
            "set protein goal to 5",   // below floor (< 20)
            "set protein goal to 500", // above ceiling (> 400)
        ]
        for query in nonMatches {
            let result = StaticOverrides.match(query.lowercased())
            if case .handler = result {
                XCTFail("Out-of-range protein goal '\(query)' should not produce a handler")
            }
        }
    }

    @MainActor
    func testStaticOverrides_CalorieGoalStillWorks() {
        let result = StaticOverrides.match("set my calorie goal to 2000")
        XCTAssertNotNil(result, "Calorie goal pattern must still match after protein goal addition")
        if case .handler = result { /* pass */ }
        else { XCTFail("Calorie goal should return .handler") }
    }
}
