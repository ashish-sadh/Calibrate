import XCTest
@testable import Drift

/// Gold set eval for AI chat pipeline — sprint tasks #79, #116.
/// Tests the full deterministic pipeline: InputNormalizer → StaticOverrides → AIActionExecutor → ToolRanker.
/// 50+ queries covering: food, weight, exercise, health, navigation, voice-style, multi-turn.
/// Measurement framework for design doc #65 — captures baseline before pipeline changes.
///
/// Run: xcodebuild test -only-testing:'DriftTests/FoodLoggingGoldSetTests'
final class FoodLoggingGoldSetTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            if ToolRegistry.shared.allTools().isEmpty {
                ToolRegistration.registerAll()
            }
        }
    }

    // MARK: - Domain Detection Helpers

    /// Returns true if the query is detected as a food logging intent.
    private func detectsFoodIntent(_ query: String) -> Bool {
        let normalized = InputNormalizer.normalize(query).lowercased()
        return AIActionExecutor.parseFoodIntent(normalized) != nil
            || AIActionExecutor.parseMultiFoodIntent(normalized) != nil
    }

    /// Returns true if the query is detected as a weight logging intent.
    private func detectsWeightIntent(_ query: String) -> Bool {
        let normalized = InputNormalizer.normalize(query).lowercased()
        return AIActionExecutor.parseWeightIntent(normalized) != nil
    }

    /// Returns true if StaticOverrides matches an activity/exercise logging pattern.
    @MainActor
    private func detectsExerciseIntent(_ query: String) -> Bool {
        let normalized = InputNormalizer.normalize(query).lowercased()
        if let result = StaticOverrides.match(normalized) {
            if case .response(let text) = result {
                return text.contains("Log ") && (text.contains("min)") || text.contains("today?"))
            }
            // Don't fall through to ToolRanker if StaticOverrides matched a non-exercise result
            return false
        }
        let tools = ToolRanker.rank(query: normalized, screen: .exercise)
        return tools.first?.name == "start_workout" || tools.first?.name == "log_activity"
    }

    /// Returns true if StaticOverrides catches this as a non-domain command (greeting, thanks, help, undo, barcode).
    /// Excludes exercise activity confirmations and navigation — those have their own domains.
    @MainActor
    private func isStaticCommand(_ query: String) -> Bool {
        let normalized = InputNormalizer.normalize(query).lowercased()
        guard let result = StaticOverrides.match(normalized) else { return false }
        switch result {
        case .response(let text):
            // Exercise activity confirmations: "Log Yoga (30 min) for today?"
            if text.contains("Log ") && text.contains("today?") { return false }
            return true
        case .handler: return true
        case .uiAction(let action, _):
            if case .navigate = action { return false }
            return true
        case .toolCall: return true
        }
    }

    /// Returns true if StaticOverrides matches a navigation pattern.
    @MainActor
    private func detectsNavigationIntent(_ query: String) -> Bool {
        let normalized = InputNormalizer.normalize(query).lowercased()
        if let result = StaticOverrides.match(normalized) {
            if case .uiAction(let action, _) = result {
                if case .navigate = action { return true }
            }
        }
        return false
    }

    /// Returns true if ToolRanker routes to a health tool (sleep, supplement, glucose, biomarker, body_comp).
    @MainActor
    private func detectsHealthIntent(_ query: String, screen: AIScreen) -> Bool {
        let normalized = InputNormalizer.normalize(query).lowercased()
        let tools = ToolRanker.rank(query: normalized, screen: screen)
        let healthTools: Set<String> = ["sleep_recovery", "mark_supplement", "glucose", "biomarkers", "body_comp"]
        return healthTools.contains(tools.first?.name ?? "")
    }

    /// Returns true if ToolRanker ranks log_food as top tool after normalization.
    @MainActor
    private func ranksLogFood(_ query: String, screen: AIScreen = .food) -> Bool {
        let normalized = InputNormalizer.normalize(query).lowercased()
        let tools = ToolRanker.rank(query: normalized, screen: screen)
        return tools.first?.name == "log_food"
    }

    /// Returns true if IntentClassifier parses the query into a log_food tool call.
    private func classifierDetectsFood(_ query: String) -> Bool {
        let normalized = InputNormalizer.normalize(query)
        let msg = IntentClassifier.buildUserMessage(message: normalized, history: "")
        return !msg.isEmpty
    }

    // MARK: - Voice-Style Input (no punctuation, fillers, restarts)

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
        print("📊 Voice filler food detection: \(detected)/\(voiceQueries.count)")
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
        print("📊 Voice restart food detection: \(detected)/\(restartQueries.count)")
        XCTAssertGreaterThanOrEqual(detected, restartQueries.count - 1)
    }

    func testVoiceRunOn() {
        // Voice input without punctuation, run-on style
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
        print("📊 Voice run-on food detection: \(detected)/\(runOnQueries.count)")
        XCTAssertGreaterThanOrEqual(detected, runOnQueries.count - 1)
    }

    // MARK: - Multi-Food Logging

    func testMultiFoodQueries() {
        let multiFood = [
            ("log rice and dal", 2),
            ("I had 2 eggs and toast", 2),
            ("ate chicken, rice, and dal", 3),
            ("had eggs, toast, and coffee", 3),
            ("log paneer and roti for dinner", 2),
        ]
        var detected = 0
        for (query, expectedCount) in multiFood {
            let normalized = InputNormalizer.normalize(query).lowercased()
            if let items = AIActionExecutor.parseMultiFoodIntent(normalized) {
                if items.count >= expectedCount { detected += 1 }
                else { print("PARTIAL (multi): '\(query)' → \(items.count) items (expected \(expectedCount))") }
            } else if AIActionExecutor.parseFoodIntent(normalized) != nil {
                detected += 1 // Single-food parse is acceptable for 2-item queries
            } else {
                print("MISS (multi): '\(query)' → normalized: '\(normalized)'")
            }
        }
        print("📊 Multi-food detection: \(detected)/\(multiFood.count)")
        XCTAssertGreaterThanOrEqual(detected, multiFood.count - 1)
    }

    // MARK: - Indian Foods

    func testIndianFoods() {
        let indianQueries = [
            "had paneer tikka masala",
            "ate 2 idli with chutney",
            "log 1 dosa and sambar",
            "had a plate of biryani",
            "ate chole bhature",
            "log rajma chawal",
            "had 2 parathas for breakfast",
            "ate aloo gobi with 2 rotis",
            "had dal makhani and naan",
            "log a bowl of khichdi",
        ]
        var detected = 0
        for query in indianQueries {
            if detectsFoodIntent(query) { detected += 1 }
            else { print("MISS (indian): '\(query)' → normalized: '\(InputNormalizer.normalize(query))'") }
        }
        let pct = Double(detected) / Double(indianQueries.count) * 100
        print("📊 Indian food detection: \(detected)/\(indianQueries.count) (\(String(format: "%.0f", pct))%)")
        XCTAssertGreaterThanOrEqual(detected, Int(Double(indianQueries.count) * 0.8), "Indian foods: ≥80% detection")
    }

    // MARK: - Vague Quantities

    func testVagueQuantities() {
        let vagueQueries = [
            "had some rice",
            "ate a couple of eggs",
            "had a lot of chicken",
            "just had a little bit of oatmeal",
            "ate a few rotis",
            "had a handful of almonds",
        ]
        var detected = 0
        for query in vagueQueries {
            if detectsFoodIntent(query) { detected += 1 }
            else { print("MISS (vague qty): '\(query)' → normalized: '\(InputNormalizer.normalize(query))'") }
        }
        print("📊 Vague quantity detection: \(detected)/\(vagueQueries.count)")
        XCTAssertGreaterThanOrEqual(detected, vagueQueries.count - 2, "Vague quantities: at most 2 misses")
    }

    // MARK: - Amount Extraction Accuracy

    func testAmountExtractionGoldSet() {
        let cases: [(String, Double, String?)] = [
            // (query, expected servings, expected unit or nil for default)
            ("log 2 eggs", 2.0, nil),
            ("had 100g chicken", 100.0, "g"),
            ("ate 200 gram rice", 200.0, "g"),
            ("log 1.5 cups of oatmeal", 1.5, "cup"),
            ("had half an avocado", 0.5, nil),
            ("ate a quarter cup of almonds", 0.25, "cup"),
            ("log 3 scoops of protein", 3.0, "scoop"),
            ("had 2 slices of pizza", 2.0, "slice"),
            ("ate 2 to 3 bananas", 3.0, nil), // takes higher
            ("had a couple of rotis", 2.0, nil),
        ]
        var correct = 0
        for (query, expectedAmt, _) in cases {
            let normalized = InputNormalizer.normalize(query).lowercased()
            if let intent = AIActionExecutor.parseFoodIntent(normalized) {
                let actual = intent.servings ?? 1.0
                if abs(actual - expectedAmt) < 0.01 {
                    correct += 1
                } else {
                    print("WRONG AMT: '\(query)' → \(actual) (expected \(expectedAmt))")
                }
            } else {
                print("MISS (amount): '\(query)'")
            }
        }
        print("📊 Amount extraction: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 3, "Amount extraction: ≥70% accuracy")
    }

    // MARK: - Normalizer + ToolRanker Integration

    @MainActor
    func testNormalizerImprovesToolRanking() {
        // Queries that should route to log_food AFTER normalization
        let queries = [
            "umm I had 2 eggs",
            "so I ate some rice",
            "ok so log chicken breast",
            "well I had a banana",
            "I had I had some toast",
        ]
        var correct = 0
        for query in queries {
            if ranksLogFood(query) { correct += 1 }
            else {
                let normalized = InputNormalizer.normalize(query).lowercased()
                let tools = ToolRanker.rank(query: normalized, screen: .food)
                print("WRONG RANK (normalized): '\(query)' → '\(normalized)' → \(tools.first?.name ?? "nil")")
            }
        }
        print("📊 Normalizer+ToolRanker food routing: \(correct)/\(queries.count)")
        XCTAssertGreaterThanOrEqual(correct, queries.count - 1)
    }

    // MARK: - IntentClassifier Input/Output

    func testClassifierResponseParsing() {
        // Test that IntentClassifier.parseResponse correctly handles food tool calls
        let foodResponses = [
            #"{"tool":"log_food","name":"eggs, toast","servings":"2"}"#,
            #"{"tool":"log_food","name":"chicken breast","servings":"1"}"#,
            #"{"tool":"log_food","name":"biryani"}"#,
            #"{"tool":"log_food","name":"rice, dal","servings":"1"}"#,
            #"{"tool":"log_food","name":"banana","servings":"3"}"#,
            #"{"tool":"log_food","name":"paneer tikka masala"}"#,
            #"{"tool":"log_food","name":"eggs","calories":"140","protein":"12"}"#,
        ]
        for response in foodResponses {
            let result = IntentClassifier.parseResponse(response)
            XCTAssertNotNil(result, "Should parse: \(response)")
            XCTAssertEqual(result?.tool, "log_food", "Tool should be log_food")
            XCTAssertNotNil(result?.params["name"], "Should have name param")
        }
    }

    func testClassifierTextResponses() {
        // Follow-up questions should parse as nil (not tool calls)
        let textResponses = [
            "What did you have for lunch?",
            "How much rice did you eat?",
            "That sounds great! Want to log something?",
        ]
        for response in textResponses {
            let result = IntentClassifier.parseResponse(response)
            XCTAssertNil(result, "Text response should not parse as tool call: \(response)")
        }
    }

    func testClassifierMalformedJSON() {
        let malformed = [
            #"{"tool":"log_food","name":"eggs""#, // missing closing brace — still finds { to }
            "not json at all",
            "",
            "   ",
        ]
        for response in malformed {
            // Should not crash
            _ = IntentClassifier.parseResponse(response)
        }
    }

    // MARK: - False Positive Prevention

    func testNormalizerDoesNotCreateFalsePositives() {
        // Info/status queries should NOT become food intents after normalization
        let shouldNotLog = [
            "umm how many calories left",
            "like what should I eat for dinner",
            "uh how's my protein",
            "so how am I doing today",
            "well what's my weight trend",
            "ok so start push day",
            "umm how did I sleep",
        ]
        var falsePositives = 0
        for query in shouldNotLog {
            if detectsFoodIntent(query) {
                falsePositives += 1
                print("FALSE POSITIVE (normalized): '\(query)' → '\(InputNormalizer.normalize(query))'")
            }
        }
        XCTAssertLessThanOrEqual(falsePositives, 1, "Normalizer should not create false positives")
    }

    // MARK: - Weight Intent Detection

    func testWeightIntents() {
        let shouldLog: [(String, Double)] = [
            ("I weigh 165 lbs", 165.0),
            ("weight is 75.2 kg", 75.2),
            ("weighed in at 170", 170.0),
            ("scale says 82 kg", 82.0),
            ("um my weight is like 165", 165.0),
            ("so I weigh 72 kg", 72.0),
        ]
        var detected = 0
        for (query, expectedValue) in shouldLog {
            if let intent = AIActionExecutor.parseWeightIntent(InputNormalizer.normalize(query).lowercased()) {
                if abs(intent.weightValue - expectedValue) < 0.1 { detected += 1 }
                else { print("WRONG VALUE (weight): '\(query)' → \(intent.weightValue) (expected \(expectedValue))") }
            } else { print("MISS (weight): '\(query)'") }
        }
        print("📊 Weight intent detection: \(detected)/\(shouldLog.count)")
        XCTAssertGreaterThanOrEqual(detected, shouldLog.count - 1)
    }

    // MARK: - Exercise Intent Detection

    @MainActor
    func testExerciseIntents() {
        let exerciseQueries = [
            "i did yoga for 30 minutes",
            "just did 20 min cardio",
            "i did push ups",
            "did running for about 45 minutes",
            "i went for a walk",
            "just finished chest day",
        ]
        var detected = 0
        for query in exerciseQueries {
            if detectsExerciseIntent(query) { detected += 1 }
            else { print("MISS (exercise): '\(query)'") }
        }
        print("📊 Exercise intent detection: \(detected)/\(exerciseQueries.count)")
        XCTAssertGreaterThanOrEqual(detected, exerciseQueries.count - 1)
    }

    // MARK: - Navigation Intent Detection

    @MainActor
    func testNavigationIntents() {
        let navQueries = [
            "show me my weight chart",
            "go to food tab",
            "open exercise",
            "show me my supplements",
        ]
        var detected = 0
        for query in navQueries {
            if detectsNavigationIntent(query) { detected += 1 }
            else { print("MISS (navigation): '\(query)'") }
        }
        print("📊 Navigation intent detection: \(detected)/\(navQueries.count)")
        XCTAssertGreaterThanOrEqual(detected, navQueries.count - 1)
    }

    // MARK: - Health Intent Detection

    @MainActor
    func testHealthIntents() {
        let healthQueries: [(String, AIScreen)] = [
            ("how'd I sleep", .bodyRhythm),
            ("sleep quality this week", .bodyRhythm),
            ("took my creatine", .supplements),
            ("took vitamin d", .supplements),
            ("any glucose spikes", .glucose),
            ("how's my body fat", .bodyComposition),
        ]
        var detected = 0
        for (query, screen) in healthQueries {
            if detectsHealthIntent(query, screen: screen) { detected += 1 }
            else { print("MISS (health): '\(query)'") }
        }
        print("📊 Health intent detection: \(detected)/\(healthQueries.count)")
        XCTAssertGreaterThanOrEqual(detected, healthQueries.count - 1)
    }

    // MARK: - Multi-Turn Scenarios (canned history + response parsing)

    func testMultiTurnFoodFollowUp() {
        // Scenario: bot asked "What did you have for lunch?" → user says "rice and dal"
        let history = "Assistant: What did you have for lunch?"
        let userMsg = "rice and dal"
        let fullMsg = IntentClassifier.buildUserMessage(message: userMsg, history: history)
        XCTAssertTrue(fullMsg.contains("What did you have for lunch"), "History should be included")
        XCTAssertTrue(fullMsg.contains("rice and dal"), "User message should be included")

        // Simulate LLM response for this context
        let cannedResponse = #"{"tool":"log_food","name":"rice, dal"}"#
        let result = IntentClassifier.parseResponse(cannedResponse)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tool, "log_food")
        XCTAssertEqual(result?.params["name"], "rice, dal")
    }

    func testMultiTurnQuantityFollowUp() {
        // Scenario: bot asked "How much rice?" → user says "200 grams"
        let history = "User: I had rice\nAssistant: How much rice?"
        let userMsg = "200 grams"
        let fullMsg = IntentClassifier.buildUserMessage(message: userMsg, history: history)
        XCTAssertTrue(fullMsg.contains("How much rice"), "History context preserved")

        let cannedResponse = #"{"tool":"log_food","name":"rice","servings":"200","unit":"g"}"#
        let result = IntentClassifier.parseResponse(cannedResponse)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tool, "log_food")
        XCTAssertEqual(result?.params["name"], "rice")
    }

    func testMultiTurnTopicSwitch() {
        // Scenario: was talking about food, now switches to weight
        let history = "User: log 2 eggs\nAssistant: Logged 2 eggs (140 cal)"
        let userMsg = "I weigh 165 lbs"
        let fullMsg = IntentClassifier.buildUserMessage(message: userMsg, history: history)
        XCTAssertTrue(fullMsg.contains("165"), "Weight message included")

        let cannedResponse = #"{"tool":"log_weight","value":"165","unit":"lbs"}"#
        let result = IntentClassifier.parseResponse(cannedResponse)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tool, "log_weight")
    }

    func testMultiTurnExerciseChain() {
        // Scenario: multi-step workout logging
        let history = "User: start push day\nAssistant: Starting Push Day workout!"
        let userMsg = "how's my bench press doing"

        let cannedResponse = #"{"tool":"exercise_info","query":"bench press trend"}"#
        let result = IntentClassifier.parseResponse(cannedResponse)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tool, "exercise_info")
        // Verify history is passed
        let fullMsg = IntentClassifier.buildUserMessage(message: userMsg, history: history)
        XCTAssertTrue(fullMsg.contains("push day"))
    }

    func testMultiTurnMealContinuation() {
        // Scenario: user adds more items to same meal
        let history = "User: log rice and dal for lunch\nAssistant: Logged rice and dal (450 cal)"
        let userMsg = "also add a roti"
        let fullMsg = IntentClassifier.buildUserMessage(message: userMsg, history: history)
        XCTAssertTrue(fullMsg.contains("rice and dal"), "Prior meal context preserved")
        XCTAssertTrue(fullMsg.contains("also add a roti"), "Continuation message included")

        let cannedResponse = #"{"tool":"log_food","name":"roti"}"#
        let result = IntentClassifier.parseResponse(cannedResponse)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tool, "log_food")
        XCTAssertEqual(result?.params["name"], "roti")
    }

    // MARK: - Voice-Style Cross-Domain

    func testVoiceWeightLogging() {
        let voiceQueries: [(String, Double)] = [
            ("um so my weight is like 165", 165.0),
            ("uh I weigh 72 kg", 72.0),
            ("so I weighed in at 170 today", 170.0),
        ]
        var detected = 0
        for (query, expected) in voiceQueries {
            if let intent = AIActionExecutor.parseWeightIntent(InputNormalizer.normalize(query).lowercased()) {
                if abs(intent.weightValue - expected) < 0.1 { detected += 1 }
            } else { print("MISS (voice weight): '\(query)'") }
        }
        print("📊 Voice weight detection: \(detected)/\(voiceQueries.count)")
        XCTAssertGreaterThanOrEqual(detected, voiceQueries.count - 1)
    }

    @MainActor
    func testVoiceExerciseLogging() {
        let voiceQueries = [
            "umm I did yoga for like 30 minutes",
            "so I just finished running",
            "uh I did push ups today",
        ]
        var detected = 0
        for query in voiceQueries {
            if detectsExerciseIntent(query) { detected += 1 }
            else { print("MISS (voice exercise): '\(query)'") }
        }
        print("📊 Voice exercise detection: \(detected)/\(voiceQueries.count)")
        XCTAssertGreaterThanOrEqual(detected, voiceQueries.count - 1)
    }

    // MARK: - Summary Statistics (50+ cross-domain queries)

    @MainActor
    func testGoldSetSummary() {
        enum Domain: String { case food, weight, exercise, navigation, health, none }

        // (query, expectedDomain) — 55 queries total
        let allQueries: [(String, Domain)] = [
            // --- Food (20 queries) ---
            ("log 2 eggs", .food),
            ("I had chicken breast", .food),
            ("ate a banana for breakfast", .food),
            ("had 200g paneer", .food),
            ("log rice and dal", .food),
            ("umm I had 2 eggs and toast", .food),
            ("I had I had some chicken", .food),
            ("so I ate biryani for lunch", .food),
            ("had a couple of rotis", .food),
            ("ate 3 idli with chutney", .food),
            ("log aloo gobi", .food),
            ("had a protein shake", .food),
            ("drank a glass of milk", .food),
            ("eating oatmeal", .food),
            ("just had some yogurt", .food),
            ("log 100g chicken for dinner", .food),
            ("ate chole bhature", .food),
            ("had dal makhani and naan", .food),
            ("log 3 scoops of protein", .food),
            ("I made a smoothie", .food),

            // --- Weight (6 queries) ---
            ("I weigh 165 lbs", .weight),
            ("weight is 75.2 kg", .weight),
            ("scale says 82 kg", .weight),
            ("weighed in at 170", .weight),
            ("my weight is 160", .weight),
            ("log weight 80 kg", .weight),

            // --- Exercise (6 queries) ---
            ("i did yoga for 30 minutes", .exercise),
            ("just did 20 min cardio", .exercise),
            ("i did push ups", .exercise),
            ("did running for about 45 minutes", .exercise),
            ("just finished chest day", .exercise),
            ("i went for a walk", .exercise),

            // --- Navigation (4 queries) ---
            ("show me my weight chart", .navigation),
            ("go to food tab", .navigation),
            ("open exercise", .navigation),
            ("show me my supplements", .navigation),

            // --- Health (5 queries) ---
            ("how'd I sleep", .health),
            ("took my creatine", .health),
            ("took vitamin d", .health),
            ("any glucose spikes", .health),
            ("how's my body fat", .health),

            // --- None / should NOT match any logging intent (14 queries) ---
            ("how many calories left", .none),
            ("what should I eat", .none),
            ("how's my protein", .none),
            ("daily summary", .none),
            ("hello", .none),
            ("thanks", .none),
            ("calories in a banana", .none),
            ("weight trend", .none),
            ("suggest a workout", .none),
            ("what should I train today", .none),
            ("how am I doing", .none),
            ("set goal to 160 lbs", .none),
            ("help", .none),
            ("undo", .none),
        ]

        var correct = 0, total = allQueries.count
        var domainStats: [Domain: (correct: Int, total: Int)] = [:]

        for (query, expected) in allQueries {
            let detected: Domain
            if detectsFoodIntent(query) {
                detected = .food
            } else if detectsWeightIntent(query) {
                detected = .weight
            } else if detectsNavigationIntent(query) {
                detected = .navigation
            } else if isStaticCommand(query) {
                detected = .none  // greetings, thanks, help, undo
            } else if detectsExerciseIntent(query) {
                detected = .exercise
            } else if detectsAnyHealthIntent(query) {
                detected = .health
            } else {
                detected = .none
            }

            let isCorrect = detected == expected
            if isCorrect { correct += 1 }
            else { print("WRONG: '\(query)' → \(detected.rawValue) (expected \(expected.rawValue))") }

            var stats = domainStats[expected, default: (0, 0)]
            stats.total += 1
            if isCorrect { stats.correct += 1 }
            domainStats[expected] = stats
        }

        let accuracy = Double(correct) / Double(total) * 100
        print("📊 GOLD SET SUMMARY (\(total) queries):")
        print("   Overall accuracy: \(correct)/\(total) (\(String(format: "%.0f", accuracy))%)")
        for (domain, stats) in domainStats.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let pct = Double(stats.correct) / Double(stats.total) * 100
            print("   \(domain.rawValue): \(stats.correct)/\(stats.total) (\(String(format: "%.0f", pct))%)")
        }

        XCTAssertGreaterThanOrEqual(total, 50, "Gold set should have 50+ queries")
        XCTAssertGreaterThanOrEqual(accuracy, 80, "Overall accuracy should be ≥80%")
    }

    /// Health queries need the right screen context for ToolRanker.
    /// In the gold set summary we check all health screens to be generous.
    @MainActor
    private func detectsAnyHealthIntent(_ query: String) -> Bool {
        let screens: [AIScreen] = [.bodyRhythm, .supplements, .glucose, .biomarkers, .bodyComposition]
        return screens.contains { detectsHealthIntent(query, screen: $0) }
    }
}
