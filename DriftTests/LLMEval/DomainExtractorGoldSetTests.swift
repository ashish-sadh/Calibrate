import XCTest
@testable import Drift

/// Isolated DomainExtractor gold set (#239) — 50 queries covering food (25),
/// weight (10), and exercise (15) parameter extraction. This stage sits
/// *between* intent routing and tool execution: given a classified intent,
/// how accurately does the extractor pull quantities, units, names, meals,
/// and workout shapes?
///
/// Gated behind `DRIFT_DEEP_EVAL=1` — a full Gemma 4 run is ~10 min. Lite
/// sanity (3 queries) always runs when the model is present.
///
/// **Domain of truth per case:** the `expected` dict lists the minimum
/// params that must appear in the extractor output. Extras are allowed —
/// LLMs often add legitimate sugar (e.g., `meal` when the user said "for
/// lunch"). Missing keys, or keys with wrong numeric/name values, fail.
///
/// Run lite: `xcodebuild test -only-testing:'DriftLLMEvalTests/DomainExtractorGoldSetTests/testLiteSanity'`
/// Run deep: `DRIFT_DEEP_EVAL=1 xcodebuild test -only-testing:'DriftLLMEvalTests/DomainExtractorGoldSetTests'`
final class DomainExtractorGoldSetTests: XCTestCase {

    nonisolated(unsafe) static var backend: LlamaCppBackend?

    override class func setUp() {
        super.setUp()
        let path = URL(fileURLWithPath: "/tmp/gemma-4-e2b-q4_k_m.gguf")
        guard FileManager.default.fileExists(atPath: path.path) else {
            print("⚠️ Gemma 4 E2B not found at /tmp/ — DomainExtractor eval skipped")
            return
        }
        let b = LlamaCppBackend(modelPath: path)
        try? b.loadSync()
        backend = b
        print("✅ Gemma 4 E2B loaded for DomainExtractor eval")
    }

    // MARK: - Case Type

    /// A single extraction gold-set case. `expected` is the minimum set of
    /// params that must appear; extras are allowed.
    struct Case: Sendable {
        let input: String
        let tool: String
        let expected: [String: String]
        let rationale: String
    }

    // MARK: - Harness

    /// Run the extractor on one case and return whether every expected key
    /// matched (modulo case + numeric normalization). Prints a diagnostic
    /// line on failure so log readers can see WHY the case failed.
    private func runCase(_ c: Case) async -> Bool {
        guard let backend = Self.backend else { return false }
        let systemPrompt = await MainActor.run { IntentClassifier.systemPrompt }
        let response = await backend.respond(
            to: "User: \(c.input)", systemPrompt: systemPrompt
        )
        guard let intent = IntentClassifier.parseResponse(response) else {
            print("❌ [\(c.tool)] '\(c.input)' → no JSON tool call (rationale: \(c.rationale))")
            return false
        }
        let actualTool = intent.tool.replacingOccurrences(of: "()", with: "")
        guard actualTool == c.tool else {
            print("❌ [\(c.tool)] '\(c.input)' → wrong tool '\(actualTool)' (rationale: \(c.rationale))")
            return false
        }
        for (key, expectedValue) in c.expected {
            guard let actualValue = intent.params[key] else {
                print("❌ [\(c.tool)] '\(c.input)' → missing param '\(key)' (expected '\(expectedValue)')")
                return false
            }
            if !valuesMatch(expectedValue, actualValue) {
                print("❌ [\(c.tool)] '\(c.input)' → param '\(key)'='\(actualValue)' ≠ expected '\(expectedValue)'")
                return false
            }
        }
        return true
    }

    /// Forgiving value comparison: trims, case-insensitive for strings,
    /// numeric-parse for numbers so "2" and "2.0" both pass. Substring
    /// match lets "egg" match "eggs" without fighting plural morphology.
    /// Internal so unit tests can exercise it directly.
    func valuesMatch(_ expected: String, _ actual: String) -> Bool {
        let e = expected.trimmingCharacters(in: .whitespaces)
        let a = actual.trimmingCharacters(in: .whitespaces)
        if e.caseInsensitiveCompare(a) == .orderedSame { return true }
        if let ed = Double(e), let ad = Double(a) { return abs(ed - ad) < 0.01 }
        return a.lowercased().contains(e.lowercased()) || e.lowercased().contains(a.lowercased())
    }

    private func skipUnlessDeepEval() throws {
        guard ProcessInfo.processInfo.environment["DRIFT_DEEP_EVAL"] != nil else {
            throw XCTSkip("Deep eval skipped — set DRIFT_DEEP_EVAL=1 to run")
        }
    }

    // MARK: - Gold Set: Food (25)

    private let foodCases: [Case] = [
        // Integer quantities
        Case(input: "I had 2 eggs", tool: "log_food",
             expected: ["name": "egg", "servings": "2"],
             rationale: "basic integer count"),
        Case(input: "log 3 rotis for dinner", tool: "log_food",
             expected: ["name": "roti", "servings": "3", "meal": "dinner"],
             rationale: "integer + meal slot"),
        Case(input: "ate 4 samosas", tool: "log_food",
             expected: ["name": "samosa", "servings": "4"],
             rationale: "past tense + integer"),
        // Grams / explicit weight units
        Case(input: "150g chicken for lunch", tool: "log_food",
             expected: ["name": "chicken", "meal": "lunch"],
             rationale: "grams + meal — amount may be '150g' or '150'"),
        Case(input: "200 grams of rice", tool: "log_food",
             expected: ["name": "rice"],
             rationale: "grams (spelled out)"),
        Case(input: "100g paneer", tool: "log_food",
             expected: ["name": "paneer"],
             rationale: "gram suffix, no space"),
        // Millilitres
        Case(input: "250 ml milk", tool: "log_food",
             expected: ["name": "milk"],
             rationale: "millilitres"),
        Case(input: "500ml coke", tool: "log_food",
             expected: ["name": "coke"],
             rationale: "ml suffix no space"),
        // Cups / katoris / pieces (Indian food units)
        Case(input: "a cup of rice", tool: "log_food",
             expected: ["name": "rice"],
             rationale: "cup unit"),
        Case(input: "one katori dal", tool: "log_food",
             expected: ["name": "dal"],
             rationale: "katori (indian bowl)"),
        Case(input: "two pieces of chicken", tool: "log_food",
             expected: ["name": "chicken"],
             rationale: "piece count, word number"),
        // Fractions
        Case(input: "half an avocado", tool: "log_food",
             expected: ["name": "avocado"],
             rationale: "fraction word-form"),
        Case(input: "quarter cup of oats", tool: "log_food",
             expected: ["name": "oats"],
             rationale: "quarter-cup fraction"),
        // Word-number quantities
        Case(input: "had two apples", tool: "log_food",
             expected: ["name": "apple", "servings": "2"],
             rationale: "word number → digit"),
        Case(input: "log five eggs for breakfast", tool: "log_food",
             expected: ["name": "egg", "servings": "5", "meal": "breakfast"],
             rationale: "word number + meal"),
        // Implicit singular
        Case(input: "had a banana", tool: "log_food",
             expected: ["name": "banana"],
             rationale: "singular implicit 'a' → count of 1"),
        Case(input: "ate an apple", tool: "log_food",
             expected: ["name": "apple"],
             rationale: "'an' → 1"),
        // Modifiers (with / no)
        Case(input: "coffee with milk", tool: "log_food",
             expected: ["name": "coffee"],
             rationale: "modifier — 'with milk' may be dropped or kept as composed"),
        Case(input: "toast with butter", tool: "log_food",
             expected: ["name": "toast"],
             rationale: "modifier — composed food"),
        // Heavy / light
        Case(input: "heavy breakfast of oats and eggs", tool: "log_food",
             expected: ["meal": "breakfast"],
             rationale: "descriptor + multi-item"),
        // Multi-item run-ons
        Case(input: "rice and dal and broccoli", tool: "log_food",
             expected: [:],  // any valid name accepted — multi-item extraction is LLM-dependent
             rationale: "multi-item run-on — routing matters, name structure varies"),
        Case(input: "had dal and rice for lunch", tool: "log_food",
             expected: ["meal": "lunch"],
             rationale: "multi-item + meal"),
        Case(input: "sandwich and chips", tool: "log_food",
             expected: [:],
             rationale: "two items combined"),
        // Composed / branded
        Case(input: "chipotle bowl 3000 cal 30p 45c 67f", tool: "log_food",
             expected: ["name": "chipotle bowl", "calories": "3000", "protein": "30", "carbs": "45", "fat": "67"],
             rationale: "branded + macro triple (extractor gold case)"),
        // Questions that should stay as food_info
        Case(input: "calories in samosa", tool: "food_info",
             expected: ["query": "calories in samosa"],
             rationale: "regression guard — not a log_food"),
    ]

    // MARK: - Gold Set: Weight (10)

    private let weightCases: [Case] = [
        // Plain number
        Case(input: "I weigh 75 kg", tool: "log_weight",
             expected: ["value": "75", "unit": "kg"],
             rationale: "plain number + kg"),
        Case(input: "I'm 165 lbs today", tool: "log_weight",
             expected: ["value": "165", "unit": "lbs"],
             rationale: "contraction + lbs"),
        Case(input: "weight 72", tool: "log_weight",
             expected: ["value": "72"],
             rationale: "bare number — unit may default via prefs"),
        // Word number
        Case(input: "set my goal to one sixty", tool: "set_goal",
             expected: ["target": "160"],
             rationale: "word number → digit (goal, not log)"),
        Case(input: "I'm seventy five kilos", tool: "log_weight",
             expected: ["value": "75", "unit": "kg"],
             rationale: "word number + spelled unit"),
        // Decimal
        Case(input: "weighed 75.4 kg this morning", tool: "log_weight",
             expected: ["value": "75.4", "unit": "kg"],
             rationale: "decimal precision"),
        Case(input: "175.2 lbs", tool: "log_weight",
             expected: ["value": "175.2", "unit": "lbs"],
             rationale: "decimal lbs"),
        // Unit confusion (prefs override)
        Case(input: "I weigh 150", tool: "log_weight",
             expected: ["value": "150"],
             rationale: "ambiguous unit — 150 lbs plausible, 150 kg not — extractor may omit unit"),
        // Goal-vs-current framing (queries, not logs)
        Case(input: "am I under goal", tool: "weight_info",
             expected: [:],
             rationale: "query framing, not log"),
        Case(input: "weight trend", tool: "weight_info",
             expected: [:],
             rationale: "explicit query"),
    ]

    // MARK: - Gold Set: Exercise (15)

    private let exerciseCases: [Case] = [
        // Sets/reps
        Case(input: "bench 3x10 at 135", tool: "log_activity",
             expected: ["name": "bench"],
             rationale: "sets x reps @ weight — extractor can drop shape specifics, name must survive"),
        Case(input: "squats 5x5 at 225", tool: "log_activity",
             expected: ["name": "squat"],
             rationale: "strength sets x reps"),
        Case(input: "deadlifts 3x3", tool: "log_activity",
             expected: ["name": "deadlift"],
             rationale: "low-rep strength — no weight given"),
        // Bodyweight counts
        Case(input: "did 50 pushups", tool: "log_activity",
             expected: ["name": "pushup"],
             rationale: "bodyweight count — sets/reps may collapse to just name"),
        Case(input: "20 pullups today", tool: "log_activity",
             expected: ["name": "pullup"],
             rationale: "bodyweight single-set"),
        // Duration
        Case(input: "did yoga for 30 minutes", tool: "log_activity",
             expected: ["name": "yoga", "duration": "30"],
             rationale: "duration in minutes"),
        Case(input: "30 min pilates", tool: "log_activity",
             expected: ["name": "pilates", "duration": "30"],
             rationale: "duration + name"),
        Case(input: "hiked for an hour", tool: "log_activity",
             expected: ["name": "hiking", "duration": "60"],
             rationale: "hour → 60 min"),
        Case(input: "ran for 45 mins", tool: "log_activity",
             expected: ["name": "run", "duration": "45"],
             rationale: "past tense + duration"),
        // Distance (run/bike)
        Case(input: "ran 5k this morning", tool: "log_activity",
             expected: ["name": "run"],
             rationale: "distance (5k) — LLM may or may not preserve distance param"),
        Case(input: "biked 10 miles", tool: "log_activity",
             expected: ["name": "bike"],
             rationale: "distance + imperial unit"),
        // Named compound lifts
        Case(input: "heavy squat day", tool: "start_workout",
             expected: [:],
             rationale: "start_workout — no duration implied"),
        Case(input: "start push day", tool: "start_workout",
             expected: ["name": "push day"],
             rationale: "named split"),
        // Set variations (AMRAP, drop set)
        Case(input: "AMRAP pullups for time", tool: "log_activity",
             expected: ["name": "pullup"],
             rationale: "AMRAP variation"),
        // Regression: bare start
        Case(input: "let's work out", tool: "start_workout",
             expected: [:],
             rationale: "intent survives even when no activity named"),
    ]

    // MARK: - Lite Sanity (always runs when model present)

    func testLiteSanity() async throws {
        guard Self.backend != nil else { throw XCTSkip("Gemma 4 not available") }
        let lite: [Case] = [foodCases[0], weightCases[0], exerciseCases[5]]
        var pass = 0
        for c in lite {
            if await runCase(c) { pass += 1 }
        }
        print("📊 DomainExtractor Lite: \(pass)/\(lite.count)")
        // Lite is sanity only — one slip is tolerated, two breaks the build
        XCTAssertGreaterThanOrEqual(pass, 2, "Lite sanity: \(pass)/\(lite.count)")
    }

    // MARK: - Deep Tests (DRIFT_DEEP_EVAL=1)

    func testFoodExtraction() async throws {
        try skipUnlessDeepEval()
        guard Self.backend != nil else { throw XCTSkip("Gemma 4 not available") }
        var pass = 0
        for c in foodCases {
            if await runCase(c) { pass += 1 }
        }
        let pct = pass * 100 / foodCases.count
        print("📊 DomainExtractor Food: \(pass)/\(foodCases.count) (\(pct)%)")
        XCTAssertGreaterThanOrEqual(pct, 80, "Food extraction: baseline threshold")
    }

    func testWeightExtraction() async throws {
        try skipUnlessDeepEval()
        guard Self.backend != nil else { throw XCTSkip("Gemma 4 not available") }
        var pass = 0
        for c in weightCases {
            if await runCase(c) { pass += 1 }
        }
        let pct = pass * 100 / weightCases.count
        print("📊 DomainExtractor Weight: \(pass)/\(weightCases.count) (\(pct)%)")
        XCTAssertGreaterThanOrEqual(pct, 80, "Weight extraction: baseline threshold")
    }

    func testExerciseExtraction() async throws {
        try skipUnlessDeepEval()
        guard Self.backend != nil else { throw XCTSkip("Gemma 4 not available") }
        var pass = 0
        for c in exerciseCases {
            if await runCase(c) { pass += 1 }
        }
        let pct = pass * 100 / exerciseCases.count
        print("📊 DomainExtractor Exercise: \(pass)/\(exerciseCases.count) (\(pct)%)")
        XCTAssertGreaterThanOrEqual(pct, 73, "Exercise extraction: baseline threshold (sets/reps hard)")
    }

    func testOverallExtractionRate() async throws {
        try skipUnlessDeepEval()
        guard Self.backend != nil else { throw XCTSkip("Gemma 4 not available") }
        let all = foodCases + weightCases + exerciseCases
        var pass = 0
        for c in all {
            if await runCase(c) { pass += 1 }
        }
        let pct = pass * 100 / all.count
        print("📊 DomainExtractor OVERALL: \(pass)/\(all.count) (\(pct)%)")
        // Ticket target: ≥90%. Baseline assertion is 80% — raises to 90%
        // once the tuning follow-up ticket ships prompt variants.
        XCTAssertGreaterThanOrEqual(pct, 80, "Overall extraction: baseline ≥80%, ticket target ≥90%")
    }

    // MARK: - Gold Set Invariants (always run)

    func testGoldSetSize_total50() {
        XCTAssertEqual(foodCases.count + weightCases.count + exerciseCases.count, 50,
                       "Ticket spec: 50 cases total")
    }

    func testGoldSetSize_foodAtLeast25() {
        XCTAssertGreaterThanOrEqual(foodCases.count, 25, "Ticket spec: ≥25 food cases")
    }

    func testGoldSetSize_weightAtLeast10() {
        XCTAssertGreaterThanOrEqual(weightCases.count, 10, "Ticket spec: ≥10 weight cases")
    }

    func testGoldSetSize_exerciseAtLeast15() {
        XCTAssertGreaterThanOrEqual(exerciseCases.count, 15, "Ticket spec: ≥15 exercise cases")
    }

    func testAllCasesHaveNonEmptyInput() {
        let all = foodCases + weightCases + exerciseCases
        for c in all {
            XCTAssertFalse(c.input.isEmpty, "Empty input in case: '\(c.rationale)'")
        }
    }

    func testAllCasesTargetKnownTools() {
        // Whitelist — if we add a new target tool, this list must grow.
        let known: Set<String> = [
            "log_food", "food_info", "log_weight", "weight_info",
            "log_activity", "start_workout", "set_goal"
        ]
        for c in foodCases + weightCases + exerciseCases {
            XCTAssertTrue(known.contains(c.tool),
                          "Unknown tool '\(c.tool)' in case '\(c.input)'")
        }
    }

    // MARK: - Value-match helper unit tests (always run)

    func testValuesMatch_exact() {
        XCTAssertTrue(valuesMatch("rice", "rice"))
    }

    func testValuesMatch_caseInsensitive() {
        XCTAssertTrue(valuesMatch("Rice", "rice"))
    }

    func testValuesMatch_numericNormalization() {
        XCTAssertTrue(valuesMatch("2", "2.0"))
        XCTAssertTrue(valuesMatch("75.4", "75.40"))
    }

    func testValuesMatch_substring_eggEggs() {
        XCTAssertTrue(valuesMatch("egg", "eggs"))
    }

    func testValuesMatch_mismatch() {
        XCTAssertFalse(valuesMatch("rice", "banana"))
    }
}
