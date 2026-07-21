import Testing
@testable import DriftCore

@Suite struct WeightUnitConversionBoundaryTests {
    @Test func kilogramConversionsAreIdentityOperations() {
        for value in [-12.5, 0, 72.25] {
            #expect(WeightUnit.kg.convert(fromKg: value) == value)
            #expect(WeightUnit.kg.convertToKg(value) == value)
        }
    }

    @Test func poundConversionsUseTheSharedConversionFactor() {
        #expect(abs(WeightUnit.lbs.convert(fromKg: 10) - 22.0462) < 0.000_001)
        #expect(abs(WeightUnit.lbs.convertToKg(22.0462) - 10) < 0.000_001)
        #expect(abs(WeightUnit.kg.convertFromLbs(22.0462) - 10) < 0.000_001)
        #expect(abs(WeightUnit.kg.convertToLbs(10) - 22.0462) < 0.000_001)
    }

    @Test func bodyAndExerciseConversionsRoundTripFractionalValues() {
        for value in [0.0, 0.25, 137.5, 1_000.125] {
            let pounds = WeightUnit.lbs.convert(fromKg: value)
            #expect(abs(WeightUnit.lbs.convertToKg(pounds) - value) < 0.000_001)

            let storedPounds = WeightUnit.kg.convertToLbs(value)
            #expect(abs(WeightUnit.kg.convertFromLbs(storedPounds) - value) < 0.000_001)
        }
    }
}
