import Testing
@testable import DriftCore

@Suite struct ServingUnitConversionCoverageTests {
    @Test func labelsCoverEveryServingUnit() {
        let labels = Dictionary(uniqueKeysWithValues: ServingUnit.allCases.map { ($0.rawValue, $0.label) })

        #expect(labels == [
            "grams": "g",
            "ounces": "oz",
            "cups": "cup",
            "tablespoons": "tbsp",
            "teaspoons": "tsp",
            "pieces": "pc",
            "ml": "ml",
            "flOz": "fl oz",
        ])
    }

    @Test func ingredientConversionsCoverTeaspoonsAndFluidOunces() {
        let honeyTeaspoons = ServingUnit.teaspoons.toGrams(3, ingredient: .honey)
        let fluidOunces = ServingUnit.flOz.toGrams(2, ingredient: .milk)

        #expect(abs(honeyTeaspoons - 21.25) < 0.000_001)
        #expect(abs(fluidOunces - 59.147) < 0.000_001)
    }

    @Test func foodRelativeConversionsUseFixedVolumesAndServingSizeForPieces() {
        let servingSize = 30.0

        #expect(ServingUnit.grams.toGrams(75, foodServingSize: servingSize) == 75)
        #expect(ServingUnit.cups.toGrams(0.5, foodServingSize: servingSize) == 120)
        #expect(ServingUnit.tablespoons.toGrams(1.5, foodServingSize: servingSize) == 22.5)
        #expect(ServingUnit.teaspoons.toGrams(3, foodServingSize: servingSize) == 15)
        #expect(ServingUnit.pieces.toGrams(2.5, foodServingSize: servingSize) == 75)
        #expect(ServingUnit.ml.toGrams(125, foodServingSize: servingSize) == 125)
        #expect(abs(ServingUnit.flOz.toGrams(2, foodServingSize: servingSize) - 59.147) < 0.000_001)
    }
}
