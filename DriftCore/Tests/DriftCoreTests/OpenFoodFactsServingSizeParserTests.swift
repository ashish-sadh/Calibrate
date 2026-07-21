import Testing
@testable import DriftCore

/// Tier 0 — Open Food Facts serving strings are normalized without network or DB access.
struct OpenFoodFactsServingSizeParserTests {

    @Test func parsesGramsIncludingParenthesizedServingWeight() {
        #expect(OpenFoodFactsService.parseServingSize("30g") == 30)
        #expect(OpenFoodFactsService.parseServingSize("1 cup (240 g)") == 240)
        #expect(OpenFoodFactsService.parseServingSize("Serving: 42.5 G") == 42.5)
    }

    @Test func treatsMillilitersAsEquivalentGrams() {
        #expect(OpenFoodFactsService.parseServingSize("100 ml") == 100)
        #expect(OpenFoodFactsService.parseServingSize("Bottle (355ML)") == 355)
    }

    @Test func convertsFluidOuncesToGrams() throws {
        let spaced = try #require(OpenFoodFactsService.parseServingSize("8 fl oz"))
        let punctuated = try #require(OpenFoodFactsService.parseServingSize("12 fl. oz"))

        #expect(abs(spaced - 236.588) < 0.0001)
        #expect(abs(punctuated - 354.882) < 0.0001)
    }

    @Test func convertsWeightOuncesToGrams() throws {
        let parsed = try #require(OpenFoodFactsService.parseServingSize("Net weight 2.5 oz"))

        #expect(abs(parsed - 70.87375) < 0.0001)
    }

    @Test func rejectsMissingOrUnsupportedServingSizes() {
        #expect(OpenFoodFactsService.parseServingSize(nil) == nil)
        #expect(OpenFoodFactsService.parseServingSize("one slice") == nil)
        #expect(OpenFoodFactsService.parseServingSize("1 L") == nil)
    }
}
