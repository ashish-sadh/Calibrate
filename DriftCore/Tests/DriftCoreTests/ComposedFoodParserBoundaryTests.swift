@testable import DriftCore
import Testing

@Suite struct ComposedFoodParserBoundaryTests {
    @Test func commaSeparatedAdditivesPreserveOrder() throws {
        let intents = try #require(
            ComposedFoodParser.parse("log yogurt with berries, nuts, and honey")
        )

        #expect(intents.map(\.query) == ["yogurt", "berries", "nuts", "honey"])
    }

    @Test func modifiersAreRemovedFromEachAdditive() throws {
        let intents = try #require(
            ComposedFoodParser.parse(
                "log salad with some chicken, extra avocado, and a bit of dressing"
            )
        )

        #expect(intents.map(\.query) == ["salad", "chicken", "avocado", "dressing"])
    }

    @Test(arguments: ["cream and sugar", "salt and pepper", "bread and butter"])
    func knownCompoundAdditiveStaysSingle(_ additive: String) throws {
        let intents = try #require(
            ComposedFoodParser.parse("log toast with \(additive)")
        )

        #expect(intents.map(\.query) == ["toast", additive])
    }

    @Test func baseAndAdditiveQuantitiesStayOnTheirOwnIntents() throws {
        let intents = try #require(
            ComposedFoodParser.parse("log 2 slices toast with 1 tbsp peanut butter")
        )
        #expect(intents.count == 2)

        #expect(intents[0].query == "toast")
        #expect(intents[0].servings == 2)
        #expect(intents[0].gramAmount == nil)

        #expect(intents[1].query == "peanut butter")
        #expect(intents[1].servings == nil)
        #expect(intents[1].gramAmount == 15)
    }
}
