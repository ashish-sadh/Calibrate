import XCTest
@testable import DriftCore

/// Tier-0: the pure decode path of the cloud meal extractor. The cloud CALL is
/// not exercised here (that's Tier-3 eval); these lock the JSON→PhotoLogResponse
/// mapping the Describe flow depends on — on BOTH platforms (#1101).
///
/// Absorbed the iOS-side `MealTextLoggerTests` when the logger moved down to
/// DriftCore; gold cases mirror `NebiusExerciseLoggerTests`.
final class NebiusMealLoggerTests: XCTestCase {

    func testDecodesCleanJSON() {
        let raw = """
        {"items":[{"name":"Roti","grams":80,"calories":160,"protein_g":5,"carbs_g":30,"fat_g":2,"fiber_g":3,"confidence":"high"}],"overall_confidence":"high","notes":null}
        """
        let resp = NebiusMealLogger.decode(raw)
        XCTAssertEqual(resp?.items.count, 1)
        XCTAssertEqual(resp?.items.first?.name, "Roti")
        XCTAssertEqual(resp?.items.first?.calories, 160)
        XCTAssertEqual(resp?.items.first?.proteinG, 5)
    }

    func testExtractsJSONWrappedInProse() {
        let raw = """
        Sure! Here's your meal:
        ```json
        {"items":[{"name":"Dal","grams":150,"calories":180,"protein_g":9,"carbs_g":25,"fat_g":4,"fiber_g":5,"confidence":"medium"}],"overall_confidence":"medium","notes":null}
        ```
        Let me know if that looks right.
        """
        let resp = NebiusMealLogger.decode(raw)
        XCTAssertEqual(resp?.items.count, 1)
        XCTAssertEqual(resp?.items.first?.name, "Dal")
    }

    /// Indian multi-item thali — one row per distinct food, order preserved.
    func testIndianMultiItemMeal() {
        let raw = #"{"items":[{"name":"Roti","grams":160,"calories":320,"protein_g":10,"carbs_g":60,"fat_g":4,"fiber_g":6,"serving_unit":"piece","serving_amount":2,"confidence":"high"},{"name":"Dal Tadka","grams":200,"calories":220,"protein_g":11,"carbs_g":28,"fat_g":7,"fiber_g":6,"serving_unit":"bowl","serving_amount":1,"confidence":"medium"},{"name":"Curd","grams":150,"calories":90,"protein_g":5,"carbs_g":7,"fat_g":5,"fiber_g":0,"serving_unit":"bowl","serving_amount":1,"confidence":"medium"}],"overall_confidence":"medium","notes":null}"#
        let resp = NebiusMealLogger.decode(raw)
        XCTAssertEqual(resp?.items.count, 3)
        XCTAssertEqual(resp?.items.map(\.name), ["Roti", "Dal Tadka", "Curd"])
        XCTAssertEqual(resp?.items.first?.servingAmount, 2)
        XCTAssertEqual(resp?.items.first?.servingUnit, "piece")
    }

    /// #1195: an empty item list is the model ANSWERING ("no food here"), not a
    /// failure. Folding it into nil made Snap's no-food branch unreachable, so
    /// a foodless photo blamed the user's network. This pair is the contract:
    /// garbage → nil, empty → a valid response the caller interprets.
    func testEmptyItemsDecodesAsValidEmptyResponse() {
        let resp = NebiusMealLogger.decode(#"{"items":[],"overall_confidence":"low","notes":null}"#)
        XCTAssertNotNil(resp)
        XCTAssertTrue(resp?.items.isEmpty ?? false)
        XCTAssertEqual(resp?.overallConfidence, .low)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(NebiusMealLogger.decode("I couldn't parse that, sorry."))
        XCTAssertNil(NebiusMealLogger.decode(""))
    }

    /// Missing numeric macros default to 0 (older/partial replies) instead of
    /// failing the whole decode; missing confidence defaults to low.
    func testMissingMacrosAndFiberDefaultToZero() {
        let raw = #"{"items":[{"name":"Black Coffee","grams":240,"calories":5}],"overall_confidence":"high","notes":null}"#
        let resp = NebiusMealLogger.decode(raw)
        XCTAssertEqual(resp?.items.first?.proteinG, 0)
        XCTAssertEqual(resp?.items.first?.fiberG, 0)
        XCTAssertEqual(resp?.items.first?.confidence, .low)
    }

    /// Model sometimes returns "Medium"/"HIGH" — lenient case-insensitive decode.
    func testMixedCaseConfidenceDecodes() {
        let raw = #"{"items":[{"name":"Poha","grams":180,"calories":250,"protein_g":6,"carbs_g":45,"fat_g":6,"fiber_g":3,"confidence":"Medium"}],"overall_confidence":"HIGH","notes":null}"#
        let resp = NebiusMealLogger.decode(raw)
        XCTAssertEqual(resp?.items.first?.confidence, .medium)
        XCTAssertEqual(resp?.overallConfidence, .high)
    }

    func testExtractJSONObjectBalancesBraces() {
        let s = "prefix {\"a\":{\"b\":1}} suffix"
        XCTAssertEqual(CloudExtractionPolicy.extractJSONObject(s), "{\"a\":{\"b\":1}}")
    }
}
