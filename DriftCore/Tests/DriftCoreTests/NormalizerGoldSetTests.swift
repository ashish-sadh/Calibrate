import XCTest
@testable import DriftCore

/// Regression gold set for InputNormalizer + the voice-grammar / amount-extraction
/// surface that depends on it. Two layers in one file:
///   1. Pure InputNormalizer.normalize() output (filler removal, corrections, etc.)
///   2. End-to-end "voice query → AIActionExecutor.parseFoodIntent" — failures here
///      mean the normalizer didn't clean the input enough for the parser.
///
/// Deterministic: no LLM, no network. Must stay at 100% on layer 1; layer 2 has
/// known #243 gaps tracked individually per test.
///
/// Run: `cd DriftCore && swift test --filter NormalizerGoldSetTests`
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

    // MARK: - Voice grammar → food intent (was FoodLoggingGoldSet)
    //
    // These exercise the same InputNormalizer surface but assert end-to-end:
    // voice grammar gets cleaned enough that AIActionExecutor.parseFoodIntent
    // still finds the food. If a normalizer change breaks one of these,
    // it's the normalizer that needs to absorb the new pattern.

    private func detectsFoodIntent(_ query: String) -> Bool {
        let normalized = InputNormalizer.normalize(query).lowercased()
        return AIActionExecutor.parseFoodIntent(normalized) != nil
            || AIActionExecutor.parseMultiFoodIntent(normalized) != nil
    }

    func testVoiceFillerWords() {
        let voiceQueries = [
            "umm I had 2 eggs",
            "uh like I ate some rice",
            "um had a banana for breakfast",
            "like I had some chicken",
            "basically I ate 3 rotis",
        ]
        var detected = 0
        for query in voiceQueries {
            if detectsFoodIntent(query) { detected += 1 }
            else { print("MISS (voice filler): '\(query)' → normalized: '\(InputNormalizer.normalize(query))'") }
        }
        XCTAssertGreaterThanOrEqual(detected, voiceQueries.count - 1, "Voice filler: at most 1 miss")
    }

    func testVoiceRestarts() {
        let restartQueries = [
            "I had I had 2 eggs for breakfast",
            "log log rice and dal",
            "I ate I ate chicken today",
        ]
        var detected = 0
        for query in restartQueries {
            if detectsFoodIntent(query) { detected += 1 }
            else { print("MISS (voice restart): '\(query)' → normalized: '\(InputNormalizer.normalize(query))'") }
        }
        XCTAssertGreaterThanOrEqual(detected, restartQueries.count - 1)
    }

    func testVoiceRunOn() {
        let runOnQueries = [
            "so I had eggs and toast for breakfast",
            "ok so I ate some biryani for lunch",
            "well I had a protein shake after workout",
        ]
        var detected = 0
        for query in runOnQueries {
            if detectsFoodIntent(query) { detected += 1 }
            else { print("MISS (voice run-on): '\(query)' → normalized: '\(InputNormalizer.normalize(query))'") }
        }
        XCTAssertGreaterThanOrEqual(detected, runOnQueries.count - 1)
    }

    // MARK: - Amount + unit extraction (was FoodLoggingGoldSet)

    func testAmountExtractionGoldSet() {
        // (query, expected amount, isGramAmount — true means check gramAmount, false means check servings)
        let cases: [(String, Double, Bool)] = [
            ("log 2 eggs", 2.0, false),
            ("had 100g chicken", 100.0, true),
            ("ate 200 gram rice", 200.0, true),
            ("log 1.5 cups of oatmeal", 1.5, false),
            ("had half an avocado", 0.5, false),
            ("ate a quarter cup of almonds", 0.25, false),
            ("log 3 scoops of protein", 3.0, false),
            ("had 2 slices of pizza", 2.0, false),
            ("ate 2 to 3 bananas", 3.0, false), // takes higher
            ("had a couple of rotis", 2.0, false),
        ]
        var correct = 0
        for (query, expectedAmt, isGramAmount) in cases {
            let normalized = InputNormalizer.normalize(query).lowercased()
            if let intent = AIActionExecutor.parseFoodIntent(normalized) {
                let actual = isGramAmount ? (intent.gramAmount ?? 1.0) : (intent.servings ?? 1.0)
                if abs(actual - expectedAmt) < 0.01 {
                    correct += 1
                } else {
                    print("WRONG AMT: '\(query)' → \(actual) (expected \(expectedAmt))")
                }
            } else {
                print("MISS (amount): '\(query)'")
            }
        }
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "Amount extraction: ≥90% accuracy")
    }

    /// Hard parsing cases — implicit quantity (#243). "lots of" and bare
    /// "couple" are known pipeline gaps, tracked as follow-ups.
    func testImplicitQuantityDetection() {
        let detectCases = [
            "I had rice",
            "ate some chicken",
            "had a bit of daal",
            "had lots of broccoli",
        ]
        var detected = 0
        for query in detectCases {
            if detectsFoodIntent(query) { detected += 1 }
            else { print("MISS (implicit qty): '\(query)' → '\(InputNormalizer.normalize(query))'") }
        }

        // "had a couple of eggs" → servings ≈ 2
        let coupleQuery = "had a couple of eggs"
        let normalized = InputNormalizer.normalize(coupleQuery).lowercased()
        if let intent = AIActionExecutor.parseFoodIntent(normalized),
           abs((intent.servings ?? 1.0) - 2.0) < 0.01 {
            detected += 1
        }

        XCTAssertGreaterThanOrEqual(detected, 3, "Implicit quantity: ≥3/5 — gaps tracked as follow-up issues")
    }

    /// Indian units — katori, roti, glass, bowl (#243).
    func testIndianUnitDetection() {
        let cases = [
            "ate 2 katori daal",
            "ate 3 roti",
            "had a glass of chai",
            "had 1 bowl of sambar",
            "ate 2 parathas",
        ]
        var detected = 0
        for query in cases {
            if detectsFoodIntent(query) { detected += 1 }
            else { print("MISS (indian unit): '\(query)' → '\(InputNormalizer.normalize(query))'") }
        }
        XCTAssertGreaterThanOrEqual(detected, 4, "Indian units: ≥4/5 must be detected")
    }

    /// Composed food — "X with Y" parsing is a known pipeline gap (#243).
    func testComposedFoodDetection() {
        let cases = [
            "had coffee with milk",
            "had tea with honey",
            "had eggs with toast",
            "ate chicken with rice",
            "had a salad with dressing",
        ]
        var detected = 0
        for query in cases {
            if detectsFoodIntent(query) { detected += 1 }
            else { print("MISS (composed): '\(query)' → '\(InputNormalizer.normalize(query))'") }
        }
        XCTAssertGreaterThanOrEqual(detected, 3, "Composed foods: ≥3/5 — 'X with Y' parsing gaps tracked as follow-up issues")
    }

    /// Fractional amounts — "one third" and unicode fractions are known gaps (#243).
    func testFractionalAmountExtraction() {
        let cases: [(String, Double)] = [
            ("had half a pizza", 0.5),
            ("ate a quarter cup of peanut butter", 0.25),
            ("had half a bagel", 0.5),
            ("had a third of a cup of oats", 0.33),
            ("had half a sandwich", 0.5),
        ]
        var correct = 0
        for (query, expected) in cases {
            let normalized = InputNormalizer.normalize(query).lowercased()
            if let intent = AIActionExecutor.parseFoodIntent(normalized) {
                let actual = intent.servings ?? 1.0
                if abs(actual - expected) < 0.02 { correct += 1 }
                else { print("WRONG AMT (fraction): '\(query)' → servings=\(actual) (expected \(expected))") }
            } else {
                print("MISS (fraction): '\(query)'")
            }
        }
        XCTAssertGreaterThanOrEqual(correct, 2, "Fractional amounts: ≥2/5 — 'one third' and bareword fractions tracked as follow-up issues")
    }

    /// Abbreviated units — TB/tsp/c/oz are known gaps (#243).
    func testAbbreviatedUnitExtraction() {
        var correct = 0
        // Gram amount — expected to work
        let gramNorm = InputNormalizer.normalize("had 150g paneer").lowercased()
        if let intent = AIActionExecutor.parseFoodIntent(gramNorm),
           abs((intent.gramAmount ?? 0) - 150.0) < 0.01 {
            correct += 1
        }
        // Spelled-out units — expected to work
        let spelledCases: [(String, Double, Bool)] = [
            ("had 2 tablespoons of peanut butter", 2.0, false),
            ("had a teaspoon of olive oil", 1.0, false),
            ("had a cup of oatmeal", 1.0, false),
        ]
        for (query, expected, isGram) in spelledCases {
            let norm = InputNormalizer.normalize(query).lowercased()
            if let intent = AIActionExecutor.parseFoodIntent(norm) {
                let actual = isGram ? (intent.gramAmount ?? 0.0) : (intent.servings ?? 1.0)
                if abs(actual - expected) < 0.01 { correct += 1 }
            }
        }
        // "6 oz" abbreviation — detection only (oz→gram not guaranteed)
        if detectsFoodIntent("had 6 oz chicken") { correct += 1 }

        XCTAssertGreaterThanOrEqual(correct, 2, "Abbreviated units: ≥2/5 — short-form abbreviations (TB/tsp/c) tracked as follow-up issues")
    }
}
