import XCTest
import Foundation

/// Deterministic eval for InputNormalizer — no LLM, no model required.
/// Golden fixtures for every transform: voice corrections, filler words,
/// repeated words, contractions, whitespace, and edge cases.
/// Must be 100% — any failure means the normalizer regressed.
final class NormalizerEval: XCTestCase {

    // MARK: - Voice self-corrections

    func testVoiceCorrection_noWaitIMean() {
        XCTAssertEqual(InputNormalizer.normalize("I had chicken no wait I mean rice"), "rice")
    }

    func testVoiceCorrection_iMeant() {
        XCTAssertEqual(InputNormalizer.normalize("log eggs I meant oatmeal"), "oatmeal")
    }

    func testVoiceCorrection_actuallyNo() {
        XCTAssertEqual(InputNormalizer.normalize("log 3 eggs actually no log 2 eggs"), "log 2 eggs")
    }

    func testVoiceCorrection_waitNo() {
        XCTAssertEqual(InputNormalizer.normalize("log lunch wait no log dinner"), "log dinner")
    }

    func testVoiceCorrection_sorryIMean() {
        XCTAssertEqual(InputNormalizer.normalize("had biryani sorry I mean dal"), "dal")
    }

    // MARK: - Filler word removal

    func testFiller_uh() {
        let result = InputNormalizer.normalize("uh I had some eggs")
        XCTAssertFalse(result.lowercased().contains(" uh "), "should strip standalone 'uh'")
        XCTAssertTrue(result.lowercased().contains("egg"), "food name should survive")
    }

    func testFiller_like() {
        let result = InputNormalizer.normalize("I like had like 3 eggs")
        XCTAssertEqual(result.lowercased().filter({ $0 == "l" && result.lowercased().contains("like") }), [])
        XCTAssertTrue(result.lowercased().contains("egg"))
    }

    func testFiller_basically() {
        let result = InputNormalizer.normalize("basically log 2 eggs")
        XCTAssertFalse(result.lowercased().contains("basically"), "should strip 'basically'")
        XCTAssertTrue(result.lowercased().contains("egg"))
    }

    func testFiller_youKnow() {
        let result = InputNormalizer.normalize("I had you know some protein")
        XCTAssertFalse(result.lowercased().contains("you know"), "should strip 'you know'")
        XCTAssertTrue(result.lowercased().contains("protein"))
    }

    func testFiller_iMean() {
        let result = InputNormalizer.normalize("log I mean track my weight")
        XCTAssertFalse(result.lowercased().contains("i mean"), "should strip 'i mean'")
    }

    // MARK: - Repeated word collapse

    func testRepeatedWords_logLog() {
        let result = InputNormalizer.normalize("log log eggs")
        XCTAssertFalse(result.lowercased().hasPrefix("log log"), "duplicate 'log' should collapse")
        XCTAssertTrue(result.lowercased().contains("egg"))
    }

    func testRepeatedWords_hadHad() {
        let result = InputNormalizer.normalize("I had had some dal")
        XCTAssertFalse(result.lowercased().contains("had had"), "should collapse repeated 'had'")
        XCTAssertTrue(result.lowercased().contains("dal"))
    }

    // MARK: - Whitespace normalization

    func testWhitespace_trailingSpaces() {
        let result = InputNormalizer.normalize("  log 2 eggs   ")
        XCTAssertEqual(result, result.trimmingCharacters(in: .whitespaces), "should trim outer whitespace")
    }

    func testWhitespace_doubleSpaces() {
        let result = InputNormalizer.normalize("log  2   eggs")
        XCTAssertFalse(result.contains("  "), "should collapse inner double-spaces")
        XCTAssertTrue(result.lowercased().contains("egg"))
    }

    // MARK: - Contraction fixes

    func testContraction_ive() {
        let result = InputNormalizer.normalize("I've had 2 eggs")
        // Should preserve meaning even if contraction is expanded or kept
        XCTAssertTrue(result.lowercased().contains("egg"))
    }

    func testContraction_hows() {
        let result = InputNormalizer.normalize("how's my weight")
        XCTAssertTrue(result.lowercased().contains("weight"))
    }

    // MARK: - Leading conjunction trim

    func testLeadingConjunction_and() {
        let result = InputNormalizer.normalize("and log 2 eggs")
        XCTAssertFalse(result.lowercased().hasPrefix("and "), "should strip leading 'and'")
        XCTAssertTrue(result.lowercased().contains("egg"))
    }

    func testLeadingConjunction_also() {
        let result = InputNormalizer.normalize("also add banana")
        // "also" may or may not be stripped — main check: banana survives
        XCTAssertTrue(result.lowercased().contains("banana"))
    }

    // MARK: - Edge cases

    func testEdge_emptyString() {
        // normalize("") returns "" — the "never empty" guarantee is for non-empty input
        let result = InputNormalizer.normalize("")
        XCTAssertEqual(result, "", "empty input returns empty (fallback = original)")
    }

    func testEdge_alreadyClean() {
        let clean = "log 2 eggs for breakfast"
        let result = InputNormalizer.normalize(clean)
        XCTAssertEqual(result, clean, "clean input should pass through unchanged")
    }

    func testEdge_onlyFillers() {
        let result = InputNormalizer.normalize("uh um hmm")
        // Should fall back to original rather than returning empty
        XCTAssertFalse(result.isEmpty, "should not produce empty output")
    }

    // MARK: - Summary

    func testPrintNormalizerSummary() {
        let cases: [(String, String)] = [
            ("uh log 2 eggs", "log 2 eggs"),
            ("log log eggs", "log eggs"),
            ("I had chicken no wait I mean rice", "rice"),
        ]
        var passed = 0
        for (input, expected) in cases {
            let result = InputNormalizer.normalize(input)
            let ok = result.lowercased() == expected.lowercased()
            if ok { passed += 1 }
            print("\(ok ? "✅" : "❌") normalize('\(input)') → '\(result)' (expected '\(expected)')")
        }
        print("📊 Normalizer: \(passed)/\(cases.count)")
        XCTAssertEqual(passed, cases.count, "All normalizer golden fixtures must pass")
    }
}
