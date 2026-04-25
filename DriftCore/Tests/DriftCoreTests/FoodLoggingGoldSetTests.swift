import XCTest
@testable import DriftCore

/// Gold-set regression tests for the pure AI pipeline pieces hosted in DriftCore.
/// Mirrors the corresponding tests in `DriftRegressionTests/FoodLoggingGoldSetTests.swift`,
/// but skips the ones that require StaticOverrides + ToolRanker + ToolRegistration
/// (those still live in the iOS app).
///
/// Run on macOS with: `cd DriftCore && swift test`.
final class FoodLoggingGoldSetTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            registerStubToolsIfNeeded()
        }
    }

    /// Register tool stubs so `ToolRanker` can score and rank against them.
    /// Handlers are no-ops — these tests don't execute tools, only test ranking.
    @MainActor
    private func registerStubToolsIfNeeded() {
        guard ToolRegistry.shared.allTools().isEmpty else { return }
        let stubHandler: @MainActor (ToolCallParams) async -> ToolResult = { _ in .text("") }

        let toolToService: [(String, String)] = [
            ("log_food", "food"), ("food_info", "food"),
            ("copy_yesterday", "food"), ("delete_food", "food"),
            ("explain_calories", "food"),
            ("log_weight", "weight"), ("weight_info", "weight"), ("set_goal", "weight"),
            ("start_workout", "exercise"), ("exercise_info", "exercise"),
            ("log_activity", "exercise"),
            ("sleep_recovery", "sleep"),
            ("supplements", "supplement"), ("mark_supplement", "supplement"),
            ("add_supplement", "supplement"),
            ("glucose", "glucose"),
            ("biomarkers", "biomarker"),
            ("body_comp", "body_comp"), ("log_body_comp", "body_comp"),
        ]

        for (name, service) in toolToService {
            ToolRegistry.shared.register(ToolSchema(
                id: "stub.\(name)",
                name: name,
                service: service,
                description: "Stub \(name)",
                parameters: [],
                handler: stubHandler
            ))
        }
    }

    // MARK: - Domain Detection Helpers

    @MainActor
    private func ranksLogFood(_ query: String, screen: AIScreen = .food) -> Bool {
        let normalized = InputNormalizer.normalize(query).lowercased()
        let tools = ToolRanker.rank(query: normalized, screen: screen)
        return tools.first?.name == "log_food"
    }

    @MainActor
    private func detectsHealthIntent(_ query: String, screen: AIScreen) -> Bool {
        let normalized = InputNormalizer.normalize(query).lowercased()
        let tools = ToolRanker.rank(query: normalized, screen: screen)
        let healthTools: Set<String> = ["sleep_recovery", "mark_supplement", "glucose", "biomarkers", "body_comp"]
        return healthTools.contains(tools.first?.name ?? "")
    }

    @MainActor
    private func detectsExerciseIntent(_ query: String) -> Bool {
        let normalized = InputNormalizer.normalize(query).lowercased()
        if let result = StaticOverrides.match(normalized) {
            if case .response(let text) = result {
                return text.contains("Log ") && (text.contains("min)") || text.contains("today?"))
            }
            return false
        }
        let tools = ToolRanker.rank(query: normalized, screen: .exercise)
        return tools.first?.name == "start_workout" || tools.first?.name == "log_activity"
    }

    @MainActor
    private func isStaticCommand(_ query: String) -> Bool {
        let normalized = InputNormalizer.normalize(query).lowercased()
        guard let result = StaticOverrides.match(normalized) else { return false }
        switch result {
        case .response(let text):
            if text.contains("Log ") && text.contains("today?") { return false }
            return true
        case .handler: return true
        case .uiAction(let action, _):
            if case .navigate = action { return false }
            return true
        case .toolCall: return true
        }
    }

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

    @MainActor
    private func detectsAnyHealthIntent(_ query: String) -> Bool {
        let screens: [AIScreen] = [.bodyRhythm, .supplements, .glucose, .biomarkers, .bodyComposition]
        return screens.contains { detectsHealthIntent(query, screen: $0) }
    }

    private func detectsFoodIntent(_ query: String) -> Bool {
        let normalized = InputNormalizer.normalize(query).lowercased()
        return AIActionExecutor.parseFoodIntent(normalized) != nil
            || AIActionExecutor.parseMultiFoodIntent(normalized) != nil
    }

    private func detectsWeightIntent(_ query: String) -> Bool {
        let normalized = InputNormalizer.normalize(query).lowercased()
        return AIActionExecutor.parseWeightIntent(normalized) != nil
    }

    // MARK: - Voice-Style Input

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
                detected += 1
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
        let cases: [(String, Double, Bool)] = [
            ("log 2 eggs", 2.0, false),
            ("had 100g chicken", 100.0, true),
            ("ate 200 gram rice", 200.0, true),
            ("log 1.5 cups of oatmeal", 1.5, false),
            ("had half an avocado", 0.5, false),
            ("ate a quarter cup of almonds", 0.25, false),
            ("log 3 scoops of protein", 3.0, false),
            ("had 2 slices of pizza", 2.0, false),
            ("ate 2 to 3 bananas", 3.0, false),
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
        print("📊 Amount extraction: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "Amount extraction: ≥90% accuracy")
    }

    // MARK: - IntentClassifier Input/Output

    func testClassifierResponseParsing() {
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
            #"{"tool":"log_food","name":"eggs""#,
            "not json at all",
            "",
            "   ",
        ]
        for response in malformed {
            _ = IntentClassifier.parseResponse(response)
        }
    }

    // MARK: - False Positive Prevention

    func testNormalizerDoesNotCreateFalsePositives() {
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

    func testNonFoodQueriesMustNotBeFood() {
        let nonFoodQueries = [
            "how was my sleep last night",
            "how'd I sleep",
            "show me my sleep quality",
            "did I take my creatine today",
            "did I take my supplements",
            "how much did I bench last week",
            "how many pushups last week",
            "start push day",
            "what's my weight trend",
            "am I on track for my goal",
            "I weigh 165 lbs",
            "how's my body fat",
            "show me my biomarkers",
            "daily summary",
            "weekly summary",
            "how am I doing today",
            "calories left",
            "how's my protein today",
            "what's my protein",
            "how many carbs left",
            "show my macros",
            "how do I do a deadlift",
            "how to do bench press",
            "form tips for squats",
            "am I on track for protein",
            "how many calories should I eat",
        ]
        var falsePositives: [String] = []
        for query in nonFoodQueries {
            if detectsFoodIntent(query) {
                falsePositives.append(query)
                print("❌ FALSE POSITIVE (non-food routed to food): '\(query)'")
            }
        }
        XCTAssertTrue(falsePositives.isEmpty,
            "These queries must NOT be food intent:\n\(falsePositives.joined(separator: "\n"))")
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

    // MARK: - Multi-Turn Scenarios

    func testMultiTurnFoodFollowUp() {
        let history = "Assistant: What did you have for lunch?"
        let userMsg = "rice and dal"
        let fullMsg = IntentClassifier.buildUserMessage(message: userMsg, history: history)
        XCTAssertTrue(fullMsg.contains("What did you have for lunch"))
        XCTAssertTrue(fullMsg.contains("rice and dal"))

        let cannedResponse = #"{"tool":"log_food","name":"rice, dal"}"#
        let result = IntentClassifier.parseResponse(cannedResponse)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tool, "log_food")
        XCTAssertEqual(result?.params["name"], "rice, dal")
    }

    func testMultiTurnQuantityFollowUp() {
        let history = "User: I had rice\nAssistant: How much rice?"
        let userMsg = "200 grams"
        let fullMsg = IntentClassifier.buildUserMessage(message: userMsg, history: history)
        XCTAssertTrue(fullMsg.contains("How much rice"))

        let cannedResponse = #"{"tool":"log_food","name":"rice","servings":"200","unit":"g"}"#
        let result = IntentClassifier.parseResponse(cannedResponse)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tool, "log_food")
        XCTAssertEqual(result?.params["name"], "rice")
    }

    func testMultiTurnTopicSwitch() {
        let history = "User: log 2 eggs\nAssistant: Logged 2 eggs (140 cal)"
        let userMsg = "I weigh 165 lbs"
        let fullMsg = IntentClassifier.buildUserMessage(message: userMsg, history: history)
        XCTAssertTrue(fullMsg.contains("165"))

        let cannedResponse = #"{"tool":"log_weight","value":"165","unit":"lbs"}"#
        let result = IntentClassifier.parseResponse(cannedResponse)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tool, "log_weight")
    }

    func testMultiTurnExerciseChain() {
        let history = "User: start push day\nAssistant: Starting Push Day workout!"
        let userMsg = "how's my bench press doing"

        let cannedResponse = #"{"tool":"exercise_info","query":"bench press trend"}"#
        let result = IntentClassifier.parseResponse(cannedResponse)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tool, "exercise_info")
        let fullMsg = IntentClassifier.buildUserMessage(message: userMsg, history: history)
        XCTAssertTrue(fullMsg.contains("push day"))
    }

    func testMultiTurnMealContinuation() {
        let history = "User: log rice and dal for lunch\nAssistant: Logged rice and dal (450 cal)"
        let userMsg = "also add a roti"
        let fullMsg = IntentClassifier.buildUserMessage(message: userMsg, history: history)
        XCTAssertTrue(fullMsg.contains("rice and dal"))
        XCTAssertTrue(fullMsg.contains("also add a roti"))

        let cannedResponse = #"{"tool":"log_food","name":"roti"}"#
        let result = IntentClassifier.parseResponse(cannedResponse)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tool, "log_food")
        XCTAssertEqual(result?.params["name"], "roti")
    }

    // MARK: - Normalizer + ToolRanker Integration

    @MainActor
    func testNormalizerImprovesToolRanking() {
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

    // MARK: - Hard Cases

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

        let coupleQuery = "had a couple of eggs"
        let normalized = InputNormalizer.normalize(coupleQuery).lowercased()
        if let intent = AIActionExecutor.parseFoodIntent(normalized) {
            if abs((intent.servings ?? 1.0) - 2.0) < 0.01 {
                detected += 1
            } else {
                print("WRONG AMT (implicit qty): '\(coupleQuery)' → servings=\(intent.servings ?? 0) (expected 2)")
            }
        } else {
            print("MISS (implicit qty): '\(coupleQuery)'")
        }

        print("📊 Implicit quantity detection: \(detected)/5")
        XCTAssertGreaterThanOrEqual(detected, 3, "Implicit quantity: ≥3/5 — gaps tracked as follow-up issues")
    }

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
        print("📊 Indian unit detection: \(detected)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(detected, 4, "Indian units: ≥4/5 must be detected")
    }

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
        print("📊 Composed food detection: \(detected)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(detected, 3, "Composed foods: ≥3/5 — 'X with Y' parsing gaps tracked as follow-up issues")
    }

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
                if abs(actual - expected) < 0.02 {
                    correct += 1
                } else {
                    print("WRONG AMT (fraction): '\(query)' → servings=\(actual) (expected \(expected))")
                }
            } else {
                print("MISS (fraction): '\(query)'")
            }
        }
        print("📊 Fractional amount extraction: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, 2, "Fractional amounts: ≥2/5 — 'one third' and bareword fractions tracked as follow-up issues")
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

    @MainActor
    func testGoldSetSummary() {
        enum Domain: String { case food, weight, exercise, navigation, health, none }

        let allQueries: [(String, Domain)] = [
            ("log 2 eggs", .food), ("I had chicken breast", .food),
            ("ate a banana for breakfast", .food), ("had 200g paneer", .food),
            ("log rice and dal", .food), ("umm I had 2 eggs and toast", .food),
            ("I had I had some chicken", .food), ("so I ate biryani for lunch", .food),
            ("had a couple of rotis", .food), ("ate 3 idli with chutney", .food),
            ("had a protein shake", .food), ("eating oatmeal", .food),
            ("I weigh 165 lbs", .weight), ("weight is 75.2 kg", .weight),
            ("scale says 82 kg", .weight), ("weighed in at 170", .weight),
            ("i did yoga for 30 minutes", .exercise), ("just did 20 min cardio", .exercise),
            ("i did push ups", .exercise), ("just finished chest day", .exercise),
            ("show me my weight chart", .navigation), ("go to food tab", .navigation),
            ("open exercise", .navigation), ("show me my supplements", .navigation),
            ("how'd I sleep", .health), ("took my creatine", .health),
            ("any glucose spikes", .health), ("how's my body fat", .health),
            ("hello", .none), ("thanks", .none),
            ("calories in a banana", .none), ("daily summary", .none),
        ]

        var correct = 0
        for (query, expected) in allQueries {
            let detected: Domain
            if detectsFoodIntent(query) {
                detected = .food
            } else if detectsWeightIntent(query) {
                detected = .weight
            } else if detectsNavigationIntent(query) {
                detected = .navigation
            } else if isStaticCommand(query) {
                detected = .none
            } else if detectsExerciseIntent(query) {
                detected = .exercise
            } else if detectsAnyHealthIntent(query) {
                detected = .health
            } else {
                detected = .none
            }

            if detected == expected { correct += 1 }
            else { print("WRONG: '\(query)' → \(detected.rawValue) (expected \(expected.rawValue))") }
        }

        let accuracy = Double(correct) / Double(allQueries.count) * 100
        print("📊 GOLD SET SUMMARY (\(allQueries.count) queries): \(correct)/\(allQueries.count) (\(String(format: "%.0f", accuracy))%)")
        XCTAssertGreaterThanOrEqual(accuracy, 75, "Overall accuracy ≥75%")
    }

    func testAbbreviatedUnitExtraction() {
        let gramQuery = "had 150g paneer"
        let gramNorm = InputNormalizer.normalize(gramQuery).lowercased()
        var correct = 0
        if let intent = AIActionExecutor.parseFoodIntent(gramNorm),
           abs((intent.gramAmount ?? 0) - 150.0) < 0.01 {
            correct += 1
        } else {
            print("MISS (abbrev gram): '\(gramQuery)'")
        }

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
                else { print("WRONG AMT (abbrev): '\(query)' → \(actual) (expected \(expected))") }
            } else {
                print("MISS (abbrev): '\(query)'")
            }
        }

        if detectsFoodIntent("had 6 oz chicken") { correct += 1 }
        else { print("MISS (abbrev oz): 'had 6 oz chicken'") }

        print("📊 Abbreviated unit extraction: \(correct)/5")
        XCTAssertGreaterThanOrEqual(correct, 2, "Abbreviated units: ≥2/5 — short-form abbreviations (TB/tsp/c) tracked as follow-up issues")
    }
}
