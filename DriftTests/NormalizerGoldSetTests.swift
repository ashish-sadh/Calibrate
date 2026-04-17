import XCTest
@testable import Drift

/// Regression gold set for InputNormalizer — sprint task #164.
/// Deterministic: no LLM, no network. Must stay at 100%.
///
/// Run: xcodebuild test -only-testing:'DriftTests/NormalizerGoldSetTests'
final class NormalizerGoldSetTests: XCTestCase {

    // MARK: - Single-Word Fillers

    func testRemovesUm() {
        XCTAssertEqual(InputNormalizer.normalize("um I had 2 eggs"), "I had 2 eggs")
    }

    func testRemovesUh() {
        XCTAssertEqual(InputNormalizer.normalize("uh log rice"), "log rice")
    }

    func testRemovesLike() {
        XCTAssertEqual(InputNormalizer.normalize("I had like 3 bananas"), "I had 3 bananas")
    }

    func testRemovesBasically() {
        XCTAssertEqual(InputNormalizer.normalize("I basically had chicken"), "I had chicken")
    }

    // MARK: - Multi-Word Fillers

    func testRemovesYouKnow() {
        XCTAssertEqual(InputNormalizer.normalize("you know I had breakfast"), "I had breakfast")
    }

    func testRemovesYouKnowWhat() {
        XCTAssertEqual(InputNormalizer.normalize("you know what log my lunch"), "log my lunch")
    }

    func testRemovesSoLike() {
        XCTAssertEqual(InputNormalizer.normalize("I had so like 200 grams of rice"), "I had 200 grams of rice")
    }

    func testRemovesSoBasically() {
        XCTAssertEqual(InputNormalizer.normalize("I so basically had oatmeal"), "I had oatmeal")
    }

    func testRemovesKindOf() {
        XCTAssertEqual(InputNormalizer.normalize("I had kind of a big lunch"), "I had a big lunch")
    }

    // MARK: - Leading Conjunctions

    func testStripsLeadingSo() {
        XCTAssertEqual(InputNormalizer.normalize("so log my breakfast"), "log my breakfast")
    }

    func testStripsOkSo() {
        XCTAssertEqual(InputNormalizer.normalize("ok so I want to log rice"), "I want to log rice")
    }

    func testStripsWell() {
        XCTAssertEqual(InputNormalizer.normalize("well I had eggs"), "I had eggs")
    }

    // MARK: - Mid-Sentence Corrections

    func testCorrectionNoWaitIMean() {
        XCTAssertEqual(InputNormalizer.normalize("log chicken no wait I mean rice"), "rice")
    }

    func testCorrectionActuallyNo() {
        XCTAssertEqual(InputNormalizer.normalize("I had 2 eggs actually no 3 eggs"), "3 eggs")
    }

    // MARK: - Combined Voice Patterns

    func testFullVoicePipeline() {
        let result = InputNormalizer.normalize("ok so umm I basically had like chicken and rice for lunch")
        XCTAssertEqual(result, "I had chicken and rice for lunch")
    }

    func testFillerPlusCorrection() {
        let result = InputNormalizer.normalize("um so log chicken no wait I mean rice and dal")
        XCTAssertTrue(result.contains("rice") && result.contains("dal"))
        XCTAssertFalse(result.contains("chicken"))
    }

    func testSoLikeMidSentenceWithFood() {
        let result = InputNormalizer.normalize("I had so like 100 grams of oats")
        XCTAssertTrue(result.contains("100") && result.contains("oats"))
        XCTAssertFalse(result.contains("so like"))
    }

    // MARK: - Edge Cases

    func testCleanInputPassesThrough() {
        XCTAssertEqual(InputNormalizer.normalize("log 3 eggs"), "log 3 eggs")
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(InputNormalizer.normalize(""), "")
    }

    func testOnlyFillersDoNotReturnEmpty() {
        let result = InputNormalizer.normalize("um uh like")
        XCTAssertFalse(result.isEmpty)
    }
}
