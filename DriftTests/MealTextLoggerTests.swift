import XCTest
@testable import Drift

/// Parsing the Drift Coach model's reply into structured meal items. The model
/// sometimes wraps JSON in prose / code fences, so extraction must be tolerant.
/// #food-logging-reuse
final class MealTextLoggerTests: XCTestCase {

    func testDecodesCleanJSON() {
        let raw = """
        {"items":[{"name":"Roti","grams":80,"calories":160,"protein_g":5,"carbs_g":30,"fat_g":2,"fiber_g":3,"confidence":"high"}],"overall_confidence":"high","notes":null}
        """
        let resp = MealTextLogger.decode(raw)
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
        let resp = MealTextLogger.decode(raw)
        XCTAssertEqual(resp?.items.count, 1)
        XCTAssertEqual(resp?.items.first?.name, "Dal")
    }

    func testMultipleItems() {
        let raw = #"{"items":[{"name":"Rice","grams":200,"calories":260,"protein_g":5,"carbs_g":56,"fat_g":1,"fiber_g":1,"confidence":"high"},{"name":"Paneer","grams":100,"calories":265,"protein_g":18,"carbs_g":6,"fat_g":20,"fiber_g":0,"confidence":"medium"}],"overall_confidence":"high","notes":null}"#
        let resp = MealTextLogger.decode(raw)
        XCTAssertEqual(resp?.items.count, 2)
        XCTAssertEqual(resp?.items.map(\.name), ["Rice", "Paneer"])
    }

    func testEmptyItemsReturnsNil() {
        XCTAssertNil(MealTextLogger.decode(#"{"items":[],"overall_confidence":"low","notes":null}"#))
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(MealTextLogger.decode("I couldn't parse that, sorry."))
        XCTAssertNil(MealTextLogger.decode(""))
    }

    func testExtractJSONObjectBalancesBraces() {
        let s = "prefix {\"a\":{\"b\":1}} suffix"
        XCTAssertEqual(MealTextLogger.extractJSONObject(s), "{\"a\":{\"b\":1}}")
    }
}
