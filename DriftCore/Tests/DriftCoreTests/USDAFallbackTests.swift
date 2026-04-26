import XCTest
@testable import DriftCore
import Foundation

/// Deterministic unit tests for the USDA fallback path (no network, no LLM).
/// Live USDA queries live in `DriftLLMEvalMacOS/USDAFallbackEval.swift`
/// (gated by DRIFT_USDA_EVAL=1).
@MainActor
final class USDAFallbackTests: XCTestCase {

    // MARK: - FoodItem struct

    func testFoodItem_constructsAndPreservesValues() {
        let item = USDAFoodService.FoodItem(
            name: "Chicken Breast",
            calories: 165,
            proteinG: 31,
            carbsG: 0,
            fatG: 3.6,
            fiberG: 0,
            servingSizeG: 100
        )
        XCTAssertEqual(item.name, "Chicken Breast")
        XCTAssertEqual(item.calories, 165)
        XCTAssertEqual(item.proteinG, 31)
        XCTAssertEqual(item.carbsG, 0)
        XCTAssertEqual(item.fatG, 3.6, accuracy: 0.01)
        XCTAssertEqual(item.servingSizeG, 100)
    }

    func testFoodItem_zeroFiberIsValid() {
        let item = USDAFoodService.FoodItem(
            name: "Egg", calories: 155, proteinG: 13, carbsG: 1.1, fatG: 11, fiberG: 0, servingSizeG: 100
        )
        XCTAssertEqual(item.fiberG, 0)
    }

    // MARK: - Fixture file

    func testFixture_fileExists() {
        XCTAssertNotNil(fixtureURL(), "top-500-foods.txt not found in DriftCoreTests resource bundle")
    }

    func testFixture_containsExpectedFoods() {
        let foods = loadFixtureFoods()
        XCTAssertGreaterThanOrEqual(foods.count, 100, "fixture should have ≥100 foods")

        let required = ["apple", "chicken breast", "biryani", "eggs", "oatmeal", "salmon"]
        for food in required {
            XCTAssertTrue(
                foods.contains(where: { $0.lowercased().contains(food.lowercased()) }),
                "fixture missing expected food: \(food)"
            )
        }
    }

    func testFixture_noBlankOrCommentLines() {
        let foods = loadFixtureFoods()
        for food in foods {
            XCTAssertFalse(food.hasPrefix("#"), "comment line leaked through: \(food)")
            XCTAssertFalse(food.isEmpty, "empty line leaked through")
        }
    }

    // MARK: - searchWithFallback — online disabled (no network)

    func testSearchWithFallback_onlineDisabled_returnsLocalOnly() async {
        let saved = Preferences.onlineFoodSearchEnabled
        Preferences.onlineFoodSearchEnabled = false
        defer { Preferences.onlineFoodSearchEnabled = saved }

        // "egg" is in local DB — should return without any USDA call
        let results = await FoodService.searchWithFallback(query: "egg")
        XCTAssertFalse(results.isEmpty, "local DB should have egg")
    }

    // Live USDA queries live in `DriftLLMEvalMacOS/USDAFallbackEval.swift`
    // (DRIFT_USDA_EVAL=1, 50-food coverage). This file stays deterministic.

    // MARK: - Helpers

    private func fixtureURL() -> URL? {
        Bundle.module.url(forResource: "top-500-foods", withExtension: "txt")
    }

    private func loadFixtureFoods() -> [String] {
        guard let url = fixtureURL(),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
