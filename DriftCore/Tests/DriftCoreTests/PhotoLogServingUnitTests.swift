@testable import DriftCore
import Testing

@Suite struct PhotoLogServingUnitTests {
    @Test func labelsAndFixedConversionsMatchEachUnit() {
        #expect(PhotoLogServingUnit.grams.label == "g")
        #expect(PhotoLogServingUnit.grams.fixedGramsPerUnit == 1)
        #expect(PhotoLogServingUnit.ounces.label == "oz")
        #expect(PhotoLogServingUnit.ounces.fixedGramsPerUnit == 28.3495)
        #expect(PhotoLogServingUnit.cups.label == "cup")
        #expect(PhotoLogServingUnit.cups.fixedGramsPerUnit == 240)
        #expect(PhotoLogServingUnit.tablespoons.label == "tbsp")
        #expect(PhotoLogServingUnit.tablespoons.fixedGramsPerUnit == 15)
        #expect(PhotoLogServingUnit.pieces.label == "piece")
        #expect(PhotoLogServingUnit.pieces.fixedGramsPerUnit == nil)
        #expect(PhotoLogServingUnit.slices.label == "slice")
        #expect(PhotoLogServingUnit.slices.fixedGramsPerUnit == nil)
    }

    @Test func parseAcceptsCommonLLMVariants() {
        #expect(PhotoLogServingUnit.parse(" gram ") == .grams)
        #expect(PhotoLogServingUnit.parse("OZ") == .ounces)
        #expect(PhotoLogServingUnit.parse("c") == .cups)
        #expect(PhotoLogServingUnit.parse("tbs") == .tablespoons)
        #expect(PhotoLogServingUnit.parse("each") == .pieces)
        #expect(PhotoLogServingUnit.parse("SLICES") == .slices)
    }

    @Test func parseRejectsMissingAndUnsupportedUnits() {
        #expect(PhotoLogServingUnit.parse(nil) == nil)
        #expect(PhotoLogServingUnit.parse("") == nil)
        #expect(PhotoLogServingUnit.parse("   ") == nil)
        #expect(PhotoLogServingUnit.parse("milliliters") == nil)
    }

    @Test func suggestedUnitUsesKeywordGroupsAndFallback() {
        #expect(PhotoLogServingUnit.suggested(forName: "Pepperoni Pizza") == .slices)
        #expect(PhotoLogServingUnit.suggested(forName: "BANANA") == .pieces)
        #expect(PhotoLogServingUnit.suggested(forName: "lentil dal") == .cups)
        #expect(PhotoLogServingUnit.suggested(forName: "Peanut Butter") == .tablespoons)
        #expect(PhotoLogServingUnit.suggested(forName: "grilled chicken") == .grams)
    }

    @Test func suggestedUnitUsesFirstMatchingCategory() {
        #expect(PhotoLogServingUnit.suggested(forName: "apple pie") == .slices)
        #expect(PhotoLogServingUnit.suggested(forName: "egg salad") == .pieces)
    }
}
