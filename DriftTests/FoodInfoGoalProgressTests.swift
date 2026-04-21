import XCTest
@testable import Drift

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
}
