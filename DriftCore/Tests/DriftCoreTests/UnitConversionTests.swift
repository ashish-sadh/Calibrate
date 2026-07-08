import XCTest
@testable import DriftCore

/// Tier-0 tests for unit conversion in AIActionExecutor.normalizeToGrams
/// and ServingUnit.toGrams. No DB, no LLM, deterministic.
///
/// Run: cd DriftCore && swift test --filter UnitConversionTests
final class UnitConversionTests: XCTestCase {

    // MARK: - normalizeToGrams

    func testNormalizeToGrams_oz() {
        let result = AIActionExecutor.normalizeToGrams(2, unit: "oz")
        XCTAssertEqual(result!, 56.699, accuracy: 0.01)
    }

    func testNormalizeToGrams_kg() {
        XCTAssertEqual(AIActionExecutor.normalizeToGrams(1, unit: "kg")!, 1000, accuracy: 0.01)
        XCTAssertEqual(AIActionExecutor.normalizeToGrams(0.5, unit: "kg")!, 500, accuracy: 0.01)
    }

    func testNormalizeToGrams_cup() {
        XCTAssertEqual(AIActionExecutor.normalizeToGrams(1, unit: "cup")!, 240, accuracy: 0.01)
        XCTAssertEqual(AIActionExecutor.normalizeToGrams(2, unit: "cups")!, 480, accuracy: 0.01)
    }

    func testNormalizeToGrams_tbsp() {
        XCTAssertEqual(AIActionExecutor.normalizeToGrams(1, unit: "tbsp")!, 15, accuracy: 0.01)
        XCTAssertEqual(AIActionExecutor.normalizeToGrams(2, unit: "tbsp")!, 30, accuracy: 0.01)
    }

    func testNormalizeToGrams_tsp() {
        XCTAssertEqual(AIActionExecutor.normalizeToGrams(1, unit: "tsp")!, 5, accuracy: 0.01)
    }

    func testNormalizeToGrams_grams_passThrough() {
        XCTAssertEqual(AIActionExecutor.normalizeToGrams(200, unit: "g")!, 200, accuracy: 0.01)
        XCTAssertEqual(AIActionExecutor.normalizeToGrams(100, unit: "gram")!, 100, accuracy: 0.01)
        XCTAssertEqual(AIActionExecutor.normalizeToGrams(50, unit: "grams")!, 50, accuracy: 0.01)
    }

    func testNormalizeToGrams_ml_passThrough() {
        XCTAssertEqual(AIActionExecutor.normalizeToGrams(240, unit: "ml")!, 240, accuracy: 0.01)
    }

    func testNormalizeToGrams_countUnits_returnsNil() {
        XCTAssertNil(AIActionExecutor.normalizeToGrams(1, unit: "scoop"))
        XCTAssertNil(AIActionExecutor.normalizeToGrams(1, unit: "piece"))
        XCTAssertNil(AIActionExecutor.normalizeToGrams(1, unit: "serving"))
        XCTAssertNil(AIActionExecutor.normalizeToGrams(1, unit: "slice"))
    }

    // MARK: - extractAmount unit conversion

    func testExtractAmount_oz_convertsToGrams() {
        let (servings, food, grams) = AIActionExecutor.extractAmount(from: "2 oz chicken")
        XCTAssertNil(servings)
        XCTAssertEqual(food.lowercased(), "chicken")
        XCTAssertEqual(grams!, 56.699, accuracy: 0.01)
    }

    // #991: a count > 10 with a food word keeps the count (was dropped + food name polluted).
    func testExtractAmount_highCount_keepsCountAndFood() {
        let (servings, food, grams) = AIActionExecutor.extractAmount(from: "15 eggs")
        XCTAssertEqual(servings, 15)
        XCTAssertEqual(food.lowercased(), "eggs")
        XCTAssertNil(grams)
    }

    // #992: a weight GOAL must not log a body-weight entry.
    func testParseWeightIntent_goalPhrasingReturnsNil() {
        XCTAssertNil(AIActionExecutor.parseWeightIntent("my weight goal is 75"))
        XCTAssertNotNil(AIActionExecutor.parseWeightIntent("i weigh 165 lbs"), "a real weigh-in still parses")
    }

    // #994: spelled-out "kilos"/"kilograms" parse as kg even when the default is lbs.
    func testParseWeightIntent_spelledOutKilos() {
        XCTAssertEqual(AIActionExecutor.parseWeightIntent("i weigh 70 kilos", defaultUnit: .lbs)?.unit, .kg)
        XCTAssertEqual(AIActionExecutor.parseWeightIntent("my weight is 68 kilograms", defaultUnit: .lbs)?.unit, .kg)
    }

    func testExtractAmount_cup_convertsToGrams() {
        // oats = 80g/cup (food-aware, was flat 240g)
        let (servings, food, grams) = AIActionExecutor.extractAmount(from: "1 cup oats")
        XCTAssertNil(servings)
        XCTAssertEqual(food.lowercased(), "oats")
        XCTAssertEqual(grams!, 80, accuracy: 0.01)
    }

    func testExtractAmount_tbsp_convertsToGrams() {
        // peanut butter has no RawIngredient match → flat 15g/tbsp
        let (servings, food, grams) = AIActionExecutor.extractAmount(from: "1 tbsp peanut butter")
        XCTAssertNil(servings)
        XCTAssertTrue(food.lowercased().contains("peanut butter"))
        XCTAssertEqual(grams!, 15, accuracy: 0.01)
    }

    func testExtractAmount_tsp_convertsToGrams() {
        // honey = 340g/cup → 340/48 ≈ 7.08g/tsp (food-aware, was flat 5g)
        let (servings, food, grams) = AIActionExecutor.extractAmount(from: "2 tsp honey")
        XCTAssertNil(servings)
        XCTAssertEqual(food.lowercased(), "honey")
        XCTAssertEqual(grams!, 340.0 / 48 * 2, accuracy: 0.5)
    }

    func testExtractAmount_kg_convertsToGrams() {
        let (servings, food, grams) = AIActionExecutor.extractAmount(from: "0.5 kg rice")
        XCTAssertNil(servings)
        XCTAssertEqual(food.lowercased(), "rice")
        XCTAssertEqual(grams!, 500, accuracy: 0.01)
    }

    func testExtractAmount_scoop_remainsServings() {
        let (servings, food, grams) = AIActionExecutor.extractAmount(from: "2 scoops protein powder")
        XCTAssertEqual(servings!, 2, accuracy: 0.01)
        XCTAssertTrue(food.lowercased().contains("protein"))
        XCTAssertNil(grams)
    }

    func testExtractAmount_halfCup_convertsToGrams() {
        // milk = 244g/cup (food-aware, was flat 240g → 120)
        let (servings, food, grams) = AIActionExecutor.extractAmount(from: "half cup milk")
        XCTAssertNil(servings)
        XCTAssertEqual(food.lowercased(), "milk")
        XCTAssertEqual(grams!, 122, accuracy: 0.5)
    }

    func testExtractAmount_twoCups_convertsToGrams() {
        // oatmeal matches oats = 80g/cup (food-aware, was flat 240g → 480)
        let (servings, food, grams) = AIActionExecutor.extractAmount(from: "2 cups oatmeal")
        XCTAssertNil(servings)
        XCTAssertEqual(food.lowercased(), "oatmeal")
        XCTAssertEqual(grams!, 160, accuracy: 0.5)
    }

    // MARK: - ServingUnit.ounces

    func testServingUnit_ounces_toGramsIngredient() {
        let result = ServingUnit.ounces.toGrams(2, ingredient: .chicken_raw)
        XCTAssertEqual(result, 56.699, accuracy: 0.01)
    }

    func testServingUnit_ounces_toGramsFoodServingSize() {
        let result = ServingUnit.ounces.toGrams(3, foodServingSize: 100)
        XCTAssertEqual(result, 85.0485, accuracy: 0.01)
    }

    func testServingUnit_ounces_label() {
        XCTAssertEqual(ServingUnit.ounces.label, "oz")
    }

    // MARK: - Gold set: food-aware unit conversion

    func testFoodAware_cup_oats() {
        let (_, food, grams) = AIActionExecutor.extractAmount(from: "2 cups oats")
        XCTAssertEqual(food.lowercased(), "oats")
        XCTAssertEqual(grams!, 160, accuracy: 0.5)
    }

    func testFoodAware_cup_rice() {
        let (_, food, grams) = AIActionExecutor.extractAmount(from: "1 cup rice")
        XCTAssertEqual(food.lowercased(), "rice")
        XCTAssertEqual(grams!, 185, accuracy: 0.5)
    }

    func testFoodAware_cup_milk() {
        let (_, food, grams) = AIActionExecutor.extractAmount(from: "1 cup milk")
        XCTAssertEqual(food.lowercased(), "milk")
        XCTAssertEqual(grams!, 244, accuracy: 0.5)
    }

    func testFoodAware_cup_dal() {
        let (_, food, grams) = AIActionExecutor.extractAmount(from: "1 cup dal")
        XCTAssertEqual(food.lowercased(), "dal")
        XCTAssertEqual(grams!, 190, accuracy: 0.5)
    }

    func testFoodAware_cup_chickpeas() {
        let (_, food, grams) = AIActionExecutor.extractAmount(from: "1 cup chickpeas")
        XCTAssertEqual(food.lowercased(), "chickpeas")
        XCTAssertEqual(grams!, 164, accuracy: 0.5)
    }

    func testFoodAware_cup_unknown_fallsBackToFlat() {
        let (_, food, grams) = AIActionExecutor.extractAmount(from: "1 cup water")
        XCTAssertEqual(food.lowercased(), "water")
        XCTAssertEqual(grams!, 240, accuracy: 0.5)
    }

    func testFoodAware_tbsp_honey() {
        let (_, food, grams) = AIActionExecutor.extractAmount(from: "2 tbsp honey")
        XCTAssertEqual(food.lowercased(), "honey")
        XCTAssertEqual(grams!, 340.0 / 16 * 2, accuracy: 0.5)
    }

    func testFoodAware_tbsp_ghee() {
        let (_, food, grams) = AIActionExecutor.extractAmount(from: "1 tbsp ghee")
        XCTAssertEqual(food.lowercased(), "ghee")
        XCTAssertEqual(grams!, 218.0 / 16, accuracy: 0.5)
    }

    func testFoodAware_tbsp_oil() {
        let (_, food, grams) = AIActionExecutor.extractAmount(from: "2 tbsp oil")
        XCTAssertEqual(food.lowercased(), "oil")
        XCTAssertEqual(grams!, 218.0 / 16 * 2, accuracy: 0.5)
    }

    func testFoodAware_tsp_honey() {
        let (_, food, grams) = AIActionExecutor.extractAmount(from: "1 tsp honey")
        XCTAssertEqual(food.lowercased(), "honey")
        XCTAssertEqual(grams!, 340.0 / 48, accuracy: 0.5)
    }

    func testFoodAware_oz_chicken() {
        let (_, food, grams) = AIActionExecutor.extractAmount(from: "8 oz chicken")
        XCTAssertEqual(food.lowercased(), "chicken")
        XCTAssertEqual(grams!, 8 * 28.3495, accuracy: 0.5)
    }

    func testFoodAware_oz_salmon() {
        let (_, food, grams) = AIActionExecutor.extractAmount(from: "4 oz salmon")
        XCTAssertEqual(food.lowercased(), "salmon")
        XCTAssertEqual(grams!, 4 * 28.3495, accuracy: 0.5)
    }

    func testFoodAware_pieces_egg() {
        let (_, food, grams) = AIActionExecutor.extractAmount(from: "2 pieces egg")
        XCTAssertEqual(food.lowercased(), "egg")
        XCTAssertEqual(grams!, 100, accuracy: 0.01)
    }

    func testFoodAware_pieces_banana() {
        let (_, food, grams) = AIActionExecutor.extractAmount(from: "1 piece banana")
        XCTAssertEqual(food.lowercased(), "banana")
        XCTAssertEqual(grams!, 120, accuracy: 0.01)
    }

    func testFoodAware_floz_water() {
        let (_, food, grams) = AIActionExecutor.extractAmount(from: "8 fl oz water")
        XCTAssertEqual(food.lowercased(), "water")
        XCTAssertEqual(grams!, 8 * 29.5735, accuracy: 0.01)
    }
}
