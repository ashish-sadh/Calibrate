import XCTest
@testable import DriftCore

/// Tier-0: the pure decode + message-building paths of the meal PHOTO
/// extractor. The cloud CALL is not exercised here (that's Tier-3 eval).
/// `decode` is a thin pass-through to `NebiusMealLogger.decode` — these pin
/// that the photo path really does share the text path's decoder rather than
/// silently forking it (#1111).
final class NebiusMealPhotoLoggerTests: XCTestCase {

    func testDecodesCleanSingleItemPhoto() {
        let raw = """
        {"items":[{"name":"Idli","grams":150,"calories":195,"protein_g":6,"carbs_g":39,"fat_g":1,"fiber_g":2,"serving_unit":"piece","serving_amount":3,"confidence":"high"}],"overall_confidence":"high","notes":null}
        """
        let resp = NebiusMealPhotoLogger.decode(raw)
        XCTAssertEqual(resp?.items.count, 1)
        XCTAssertEqual(resp?.items.first?.name, "Idli")
        XCTAssertEqual(resp?.items.first?.grams, 150)
        // The TOTAL-plate-weight contract from the prompt: grams is the whole
        // 3-piece plate, not a per-piece value — the #1043 guardrail lives in
        // the review-row mapping (uniform servings multiplier), not here.
        XCTAssertEqual(resp?.items.first?.servingAmount, 3)
    }

    /// Multi-dish thali photo — order preserved, one row per dish.
    func testDecodesMultiItemThaliPhoto() {
        let raw = #"{"items":[{"name":"Roti","grams":80,"calories":160,"protein_g":5,"carbs_g":30,"fat_g":2,"fiber_g":3,"serving_unit":"piece","serving_amount":1,"confidence":"high"},{"name":"Dal Tadka","grams":200,"calories":220,"protein_g":11,"carbs_g":28,"fat_g":7,"fiber_g":6,"serving_unit":"bowl","serving_amount":1,"confidence":"medium"},{"name":"Jeera Rice","grams":180,"calories":250,"protein_g":5,"carbs_g":52,"fat_g":4,"fiber_g":2,"confidence":"medium"}],"overall_confidence":"medium","notes":null}"#
        let resp = NebiusMealPhotoLogger.decode(raw)
        XCTAssertEqual(resp?.items.map(\.name), ["Roti", "Dal Tadka", "Jeera Rice"])
    }

    /// #1195: "no food visible" is a SUCCESSFUL vision call — the prompt asks
    /// for `{"items":[]}` in exactly this case. It must decode, so Snap can
    /// say "couldn't spot any food" instead of claiming the cloud was
    /// unreachable.
    func testNoFoodVisibleDecodesAsValidEmptyResponse() {
        let resp = NebiusMealPhotoLogger.decode(#"{"items":[],"overall_confidence":"low","notes":null}"#)
        XCTAssertNotNil(resp)
        XCTAssertTrue(resp?.items.isEmpty ?? false)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(NebiusMealPhotoLogger.decode("Sorry, I couldn't make that out."))
        XCTAssertNil(NebiusMealPhotoLogger.decode(""))
    }

    func testExtractsJSONWrappedInProse() {
        let raw = """
        Here's what I see on the plate:
        ```json
        {"items":[{"name":"Dosa","grams":120,"calories":210,"protein_g":5,"carbs_g":38,"fat_g":5,"fiber_g":2,"confidence":"high"}],"overall_confidence":"high","notes":null}
        ```
        """
        let resp = NebiusMealPhotoLogger.decode(raw)
        XCTAssertEqual(resp?.items.first?.name, "Dosa")
    }

    // MARK: - requestMessage (pure)

    func testRequestMessageWithoutNote() {
        let message = NebiusMealPhotoLogger.requestMessage(userNote: nil)
        XCTAssertTrue(message.contains("Identify each distinct food"))
        XCTAssertFalse(message.contains("User note"))
    }

    func testRequestMessageAppendsTrimmedNote() {
        let message = NebiusMealPhotoLogger.requestMessage(userNote: "  no rice, I skipped it  ")
        XCTAssertTrue(message.contains("User note about this photo: no rice, I skipped it"))
    }

    func testRequestMessageIgnoresBlankNote() {
        let message = NebiusMealPhotoLogger.requestMessage(userNote: "   ")
        XCTAssertFalse(message.contains("User note"))
    }
}
