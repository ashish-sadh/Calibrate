@testable import DriftCore
import Testing

@Suite struct WeightGoalNutritionHelpersTests {
    @Test func minimumFatUsesSexSpecificBodyweightFloor() {
        #expect(WeightGoal.minimumFatG(bodyweightKg: 100, calorieTarget: 2_000, isFemale: true) == 80)
        #expect(WeightGoal.minimumFatG(bodyweightKg: 100, calorieTarget: 2_000, isFemale: false) == 60)
    }

    @Test func minimumFatUsesTwentyPercentOfCaloriesWhenHigher() {
        let result = WeightGoal.minimumFatG(bodyweightKg: 60, calorieTarget: 3_000, isFemale: true)

        #expect(abs(result - (3_000 * 0.20 / 9)) < 0.000_001)
    }

    @Test func minimumFatDefaultsToTwoThousandCalories() {
        let result = WeightGoal.minimumFatG(bodyweightKg: 50, calorieTarget: nil, isFemale: false)

        #expect(abs(result - (2_000 * 0.20 / 9)) < 0.000_001)
    }

    @Test(arguments: [
        (calories: 0.0, expected: 25.0),
        (calories: 1_500.0, expected: 25.0),
        (calories: 2_000.0, expected: 30.0),
        (calories: 2_500.0, expected: 35.0),
        (calories: 2_501.0, expected: 40.0),
    ])
    func defaultFiberAppliesFloorAndRoundsUp(calories: Double, expected: Double) {
        #expect(WeightGoal.defaultFiberG(calories: calories) == expected)
    }
}
