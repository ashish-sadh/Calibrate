import Testing
@testable import DriftCore

/// Tier 0 — deterministic normalization and ingredient-routing contracts.
@Suite struct PlantPointsServiceBoundaryTests {
    @Test func classificationNormalizesCaseWhitespaceAndParentheticals() {
        #expect(PlantPointsService.classify("  BANANA (medium)  ") == .plant)
        #expect(PlantPointsService.classify(" BASIL (fresh) ") == .herbSpice)
    }

    @Test func aliasesAndCanonicalNamesDeduplicate() {
        let points = PlantPointsService.calculate(from: [
            "palak", "palak paneer", "spinach",
        ])

        #expect(points.uniquePlants == ["spinach"])
        #expect(points.fullPoints == 1)
        #expect(points.plantCount == 1)
    }

    @Test func novaThreeUsesEvenASingleIngredientInsteadOfFoodName() {
        let item = PlantPointsService.FoodItem(
            name: "banana bar",
            ingredients: ["spinach"],
            novaGroup: 3
        )

        let points = PlantPointsService.calculate(from: [item])

        #expect(points.uniquePlants == ["spinach"])
        #expect(!points.uniquePlants.contains("banana"))
    }

    @Test func simpleFoodWithOneIngredientClassifiesItsName() {
        let item = PlantPointsService.FoodItem(
            name: "banana",
            ingredients: ["chicken"],
            novaGroup: nil
        )

        let points = PlantPointsService.calculate(from: [item])

        #expect(points.uniquePlants == ["banana"])
    }

    @Test func novaFourSkipsPlantIngredientsAndSpiceBlends() {
        let item = PlantPointsService.FoodItem(
            name: "vegetable curry",
            ingredients: ["spinach", "GARAM MASALA"],
            novaGroup: 4
        )

        let points = PlantPointsService.calculate(from: [item])

        #expect(points.total == 0)
        #expect(points.plantCount == 0)
    }

    @Test func spiceBlendExpansionIsCaseInsensitiveAndDeduplicated() {
        let items = [
            PlantPointsService.FoodItem(
                name: "seasoning",
                ingredients: ["GARAM MASALA", "cumin"],
                novaGroup: 3
            ),
        ]

        let points = PlantPointsService.calculate(from: items)

        #expect(points.uniqueHerbsSpices == [
            "cardamom", "cloves", "coriander", "cumin", "pepper",
        ])
        #expect(points.quarterPoints == 1.25)
        #expect(points.plantCount == 5)
    }
}
