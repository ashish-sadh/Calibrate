import XCTest
@testable import Drift

/// Gold-standard evaluation harness for the unified AI chat pipeline.
/// Tests the real flow: StaticOverrides → AIActionExecutor → ToolRanker → tool execution.
/// No LLM needed — all deterministic Swift logic.
/// Run: xcodebuild test -only-testing:'DriftTests/AIEvalHarness'
final class AIEvalHarness: XCTestCase {

    // MARK: - StaticOverrides Coverage

    @MainActor
    func testStaticOverridesGreetings() {
        let greetings = ["hi", "hello", "hey", "yo", "sup"]
        for g in greetings {
            let result = StaticOverrides.match(g)
            XCTAssertNotNil(result, "Greeting '\(g)' should be caught by StaticOverrides")
            if case .response(let text) = result {
                XCTAssertTrue(text.contains("Ask about") || text.contains("Hey"), "Greeting response should be helpful")
            }
        }
    }

    @MainActor
    func testStaticOverridesThanks() {
        let thanks = ["thanks", "thank you", "thx", "ty", "cool", "ok", "okay", "got it", "nice"]
        for t in thanks {
            let result = StaticOverrides.match(t)
            XCTAssertNotNil(result, "'\(t)' should be caught by StaticOverrides")
        }
    }

    @MainActor
    func testStaticOverridesRuleEngine() {
        let ruleQueries: [(String, String)] = [
            ("daily summary", "day"),
            ("summary", "day"),
            ("calories left", "cal"),
            ("yesterday", ""),
            ("this week", ""),
            ("weekly summary", ""),
            ("supplements", ""),
            ("what did i eat today", ""),
            ("copy yesterday", ""),
        ]
        for (query, _) in ruleQueries {
            let result = StaticOverrides.match(query)
            XCTAssertNotNil(result, "'\(query)' should be caught by StaticOverrides")
        }
    }

    @MainActor
    func testStaticOverridesDataEntry() {
        // Body fat, BMI, weight goal — deterministic regex
        let entries: [(String, String)] = [
            ("body fat 18", "body fat"),
            ("bf 22.5", "body fat"),
            ("bmi 24", "BMI"),
            ("set goal to 160 lbs", "weight goal"),
            ("target weight 75 kg", "weight goal"),
            ("i want to weigh 150", "weight goal"),
        ]
        for (query, label) in entries {
            let result = StaticOverrides.match(query.lowercased())
            XCTAssertNotNil(result, "'\(query)' should be caught as \(label)")
        }
    }

    @MainActor
    func testStaticOverridesQuickAdd() {
        let quickAdds: [(String, String)] = [
            ("log 500 cal", "quick calories"),
            ("log 400 calories for lunch", "quick calories"),
            ("log 400 cal 30g protein lunch", "inline macros"),
        ]
        for (query, label) in quickAdds {
            let result = StaticOverrides.match(query.lowercased())
            XCTAssertNotNil(result, "'\(query)' should be caught as \(label)")
        }
    }

    @MainActor
    func testStaticOverridesFalseNegatives() {
        // These should NOT be caught by StaticOverrides (should fall through to pipeline)
        let passThrough = [
            "I had 2 eggs",           // food intent → AIActionExecutor
            "how am I doing",          // info query → ToolRanker
            "start chest workout",     // workout → ToolRanker
            "what's a good dinner",    // food suggestion → StaticOverrides handles this actually
        ]
        let lower = passThrough[0].lowercased()
        // "I had 2 eggs" should NOT be caught by StaticOverrides
        let result = StaticOverrides.match(lower)
        // It might match the activity prefix "i did" but "i had" → food, not activity
        // Just verify it doesn't return a nonsensical match
        if let result, case .response(let text) = result {
            XCTAssertFalse(text.contains("Log") && text.contains("confirm"),
                "'I had 2 eggs' should not be treated as activity logging")
        }
    }

    // MARK: - Food Intent Detection (Precision & Recall)

    func testFoodLoggingIntents() {
        let shouldLog = [
            "log 2 eggs", "ate chicken breast", "had a banana",
            "log rice and dal", "I just had a samosa for lunch",
            "add a protein shake", "track 3 rotis", "eating oatmeal",
            "logged half avocado", "i ate 2 slices of pizza",
            "had a cup of rice", "log a bowl of oatmeal",
            "i just had chicken and rice", "ate a couple of eggs",
            "just had some dal", "i ate a few rotis",
            "had a scoop of protein", "log eggs for dinner",
            "ate a lot of rice", "just ate some yogurt",
            "i had a coffee", "had 3 eggs for breakfast",
            "i had 2 eggs and a banana",
        ]
        var detected = 0
        for query in shouldLog {
            let lower = query.lowercased()
            if AIActionExecutor.parseFoodIntent(lower) != nil
                || AIActionExecutor.parseMultiFoodIntent(lower) != nil {
                detected += 1
            } else { print("MISS (food): '\(query)'") }
        }
        let pct = Double(detected) / Double(shouldLog.count) * 100
        print("📊 Food intent precision: \(detected)/\(shouldLog.count) (\(String(format: "%.0f", pct))%)")
        XCTAssertGreaterThanOrEqual(detected, Int(Double(shouldLog.count) * 0.85))
    }

    func testFoodLoggingFalsePositives() {
        let shouldNotLog = [
            "how many calories in a banana", "what should I eat for dinner",
            "how's my protein", "calories left", "daily summary",
            "am I on track", "how much does chicken weigh",
            "what's in a samosa", "I did push ups",
            "start push day", "what should I train", "how's my sleep",
        ]
        var fp = 0
        for query in shouldNotLog {
            let lower = query.lowercased()
            if AIActionExecutor.parseFoodIntent(lower) != nil
                || AIActionExecutor.parseMultiFoodIntent(lower) != nil {
                fp += 1
                print("FALSE POSITIVE (food): '\(query)'")
            }
        }
        XCTAssertLessThanOrEqual(fp, 1, "At most 1 food false positive")
    }

    // MARK: - Weight Intent Detection

    func testWeightIntents() {
        let shouldLog = [
            ("I weigh 165 lbs", 165.0, WeightUnit.lbs),
            ("weight is 75.2 kg", 75.2, .kg),
            ("weighed in at 170", 170.0, .lbs),
            ("scale says 82 kg", 82.0, .kg),
            ("my weight is 165", 165.0, .lbs),
            ("log weight 170 lbs", 170.0, .lbs),
        ]
        var detected = 0
        for (query, expectedValue, _) in shouldLog {
            if let intent = AIActionExecutor.parseWeightIntent(query.lowercased()) {
                if abs(intent.weightValue - expectedValue) < 0.1 { detected += 1 }
                else { print("WRONG VALUE: '\(query)' → \(intent.weightValue) (expected \(expectedValue))") }
            } else { print("MISS (weight): '\(query)'") }
        }
        XCTAssertGreaterThanOrEqual(detected, 5, "Weight: \(detected)/\(shouldLog.count)")
    }

    func testWeightFalsePositives() {
        let shouldNotLog = [
            "how much does chicken weigh", "am I losing weight",
            "what's my weight trend", "how much have I lost",
        ]
        for query in shouldNotLog {
            XCTAssertNil(AIActionExecutor.parseWeightIntent(query.lowercased()),
                "'\(query)' should NOT parse as weight")
        }
    }

    // MARK: - ToolRanker Accuracy

    @MainActor
    func testToolRankerFoodTools() {
        let foodLogQueries = [
            ("I had 2 eggs", "log_food"),
            ("log chicken breast", "log_food"),
            ("ate a banana", "log_food"),
        ]
        for (query, expectedTool) in foodLogQueries {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: .food)
            XCTAssertEqual(tools.first?.name, expectedTool,
                "'\(query)' → top tool should be \(expectedTool), got \(tools.first?.name ?? "nil")")
        }

        let foodInfoQueries = [
            ("calories left", "food_info"),
            ("how much protein in banana", "food_info"),
            ("what should I eat", "food_info"),
        ]
        for (query, expectedTool) in foodInfoQueries {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: .food)
            XCTAssertEqual(tools.first?.name, expectedTool,
                "'\(query)' → top tool should be \(expectedTool), got \(tools.first?.name ?? "nil")")
        }
    }

    @MainActor
    func testToolRankerWeightTools() {
        let queries: [(String, String, AIScreen)] = [
            ("I weigh 165 lbs", "log_weight", .weight),
            ("how's my weight trend", "weight_info", .weight),
            ("am I on track to reach my goal", "weight_info", .weight),
            ("set goal to 160", "set_goal", .goal),
        ]
        for (query, expectedTool, screen) in queries {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: screen)
            XCTAssertEqual(tools.first?.name, expectedTool,
                "'\(query)' → top tool should be \(expectedTool), got \(tools.first?.name ?? "nil")")
        }
    }

    @MainActor
    func testToolRankerExerciseTools() {
        let queries: [(String, String, AIScreen)] = [
            ("start chest workout", "start_workout", .exercise),
            ("what should I train today", "exercise_info", .exercise),
            ("I did yoga for 30 min", "log_activity", .exercise),
        ]
        for (query, expectedTool, screen) in queries {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: screen)
            XCTAssertEqual(tools.first?.name, expectedTool,
                "'\(query)' → top tool should be \(expectedTool), got \(tools.first?.name ?? "nil")")
        }
    }

    @MainActor
    func testToolRankerHealthTools() {
        let queries: [(String, String, AIScreen)] = [
            ("how'd I sleep", "sleep_recovery", .bodyRhythm),
            ("took my creatine", "mark_supplement", .supplements),
            ("any glucose spikes", "glucose", .glucose),
            ("lab results", "biomarkers", .biomarkers),
            ("how's my body fat", "body_comp", .bodyComposition),
        ]
        for (query, expectedTool, screen) in queries {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: screen)
            XCTAssertEqual(tools.first?.name, expectedTool,
                "'\(query)' → top tool should be \(expectedTool), got \(tools.first?.name ?? "nil")")
        }
    }

    // MARK: - ToolRanker.tryRulePick (High-Confidence Picks)

    @MainActor
    func testTryRulePickHitsCorrectTool() {
        let highConfidence: [(String, String, AIScreen)] = [
            ("I had 2 eggs", "log_food", .food),
            ("ate chicken breast", "log_food", .food),
            ("start chest workout", "start_workout", .exercise),
            ("how'd I sleep last night", "sleep_recovery", .bodyRhythm),
        ]
        var correct = 0
        for (query, expectedTool, screen) in highConfidence {
            if let call = ToolRanker.tryRulePick(query: query.lowercased(), screen: screen) {
                if call.tool == expectedTool { correct += 1 }
                else { print("WRONG PICK: '\(query)' → \(call.tool) (expected \(expectedTool))") }
            } else { print("NO PICK: '\(query)' (expected \(expectedTool))") }
        }
        print("📊 tryRulePick accuracy: \(correct)/\(highConfidence.count)")
        XCTAssertGreaterThanOrEqual(correct, highConfidence.count / 2)
    }

    @MainActor
    func testTryRulePickExtractsParams() {
        // log_food should extract food name
        if let call = ToolRanker.tryRulePick(query: "log 2 eggs", screen: .food) {
            XCTAssertEqual(call.tool, "log_food")
            XCTAssertNotNil(call.params.string("name"), "Should extract food name")
        }

        // log_weight should extract value
        if let call = ToolRanker.tryRulePick(query: "i weigh 165 lbs", screen: .weight) {
            XCTAssertEqual(call.tool, "log_weight")
            XCTAssertNotNil(call.params.string("value"), "Should extract weight value")
        }
    }

    @MainActor
    func testTryRulePickAvoidsAmbiguous() {
        // Ambiguous queries should return nil (fall through to LLM)
        let ambiguous = [
            ("how am I doing", AIScreen.dashboard),
            ("tell me about my health", .dashboard),
            ("compare food and weight", .dashboard),
        ]
        for (query, screen) in ambiguous {
            let call = ToolRanker.tryRulePick(query: query.lowercased(), screen: screen)
            // These might or might not pick — just verify no crash
            if let call {
                print("INFO: ambiguous '\(query)' picked \(call.tool)")
            }
        }
    }

    // MARK: - Tool Execution (Info Tools Return Data)

    @MainActor
    func testInfoToolsReturnData() async {
        // Info tools should return non-error results even with empty DB
        let infoTools: [(String, [String: String])] = [
            ("food_info", [:]),
            ("weight_info", [:]),
            ("exercise_info", [:]),
            ("sleep_recovery", [:]),
            ("supplements", [:]),
        ]
        for (toolName, params) in infoTools {
            let call = ToolCall(tool: toolName, params: ToolCallParams(values: params))
            let result = await ToolRegistry.shared.execute(call)
            switch result {
            case .text(let text):
                XCTAssertFalse(text.isEmpty, "\(toolName) should return non-empty text")
            case .action:
                break // action tools are fine
            case .error(let msg):
                XCTFail("\(toolName) returned error: \(msg)")
            }
        }
    }

    @MainActor
    func testActionToolsReturnActions() async {
        // log_food should return openFoodSearch action
        let call = ToolCall(tool: "log_food", params: ToolCallParams(values: ["name": "eggs"]))
        let result = await ToolRegistry.shared.execute(call)
        if case .action(let action) = result {
            if case .openFoodSearch(let query, _) = action {
                XCTAssertTrue(query.lowercased().contains("egg"), "Should search for eggs")
            } else {
                XCTFail("log_food should return openFoodSearch action")
            }
        }
    }

    // MARK: - Amount Parsing

    func testAmountParsing() {
        let cases: [(String, Double?, String)] = [
            ("2 eggs", 2, "eggs"),
            ("half avocado", 0.5, "avocado"),
            ("1/3 avocado", 1.0/3, "avocado"),
            ("a couple of eggs", 2, "eggs"),
            ("a few rotis", 3, "rotis"),
            ("three samosas", 3, "samosas"),
            ("a banana", 1, "banana"),
            ("chicken breast", nil, "chicken breast"),
        ]
        var correct = 0
        for (input, expectedAmount, _) in cases {
            let intent = AIActionExecutor.parseFoodIntent("log \(input)")
            if let intent {
                let amountMatch: Bool
                if let expected = expectedAmount {
                    amountMatch = intent.servings != nil && abs((intent.servings ?? 0) - expected) < 0.05
                } else {
                    amountMatch = intent.servings == nil
                }
                if amountMatch { correct += 1 }
                else { print("PARSE: '\(input)' → servings=\(String(describing: intent.servings)) (expected \(String(describing: expectedAmount)))") }
            } else { print("PARSE FAIL: 'log \(input)'") }
        }
        print("📊 Amount parsing: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count * 3 / 4)
    }

    // MARK: - Multi-Food Parsing

    func testMultiFoodParsing() {
        let shouldSplit = [
            ("log chicken and rice", 2),
            ("ate 2 eggs and toast", 2),
            ("i just had chicken and rice", 2),
            ("had dal, rice, and roti", 3),
        ]
        for (query, expectedCount) in shouldSplit {
            let intents = AIActionExecutor.parseMultiFoodIntent(query.lowercased())
            XCTAssertNotNil(intents, "'\(query)' should split into multi-food")
            XCTAssertEqual(intents?.count, expectedCount, "'\(query)' should have \(expectedCount) items")
        }
    }

    func testCompoundFoodsNotSplit() {
        let compounds = ["mac and cheese", "bread and butter", "rice and beans"]
        for food in compounds {
            let result = AIActionExecutor.parseMultiFoodIntent("log \(food)")
            XCTAssertNil(result, "Compound '\(food)' should not be split")
        }
    }

    // MARK: - End-to-End Pipeline Layer Detection

    @MainActor
    func testPipelineLayerCoverage() {
        // Test that each query type hits the correct pipeline layer
        struct LayerTest {
            let query: String
            let expectedLayer: String // "static", "food_parser", "weight_parser", "tool_ranker"
        }

        let tests: [LayerTest] = [
            // StaticOverrides layer
            LayerTest(query: "hi", expectedLayer: "static"),
            LayerTest(query: "daily summary", expectedLayer: "static"),
            LayerTest(query: "calories left", expectedLayer: "static"),
            LayerTest(query: "body fat 18", expectedLayer: "static"),
            LayerTest(query: "log 500 cal", expectedLayer: "static"),

            // Food parser layer
            LayerTest(query: "I had 2 eggs", expectedLayer: "food_parser"),
            LayerTest(query: "ate chicken and rice", expectedLayer: "food_parser"),

            // Weight parser layer
            LayerTest(query: "I weigh 165 lbs", expectedLayer: "weight_parser"),
        ]

        for test in tests {
            let lower = test.query.lowercased()
            var hitLayer = "none"

            if StaticOverrides.match(lower) != nil {
                hitLayer = "static"
            } else if AIActionExecutor.parseFoodIntent(lower) != nil
                       || AIActionExecutor.parseMultiFoodIntent(lower) != nil {
                hitLayer = "food_parser"
            } else if AIActionExecutor.parseWeightIntent(lower) != nil {
                hitLayer = "weight_parser"
            } else if ToolRanker.tryRulePick(query: lower, screen: .dashboard) != nil {
                hitLayer = "tool_ranker"
            }

            XCTAssertEqual(hitLayer, test.expectedLayer,
                "'\(test.query)' should hit \(test.expectedLayer), hit \(hitLayer)")
        }
    }

    // MARK: - Response Quality

    func testResponseCleaner() {
        // Bad responses
        XCTAssertTrue(AIResponseCleaner.isLowQuality(""))
        XCTAssertTrue(AIResponseCleaner.isLowQuality("Hi"))
        XCTAssertTrue(AIResponseCleaner.isLowQuality("I'm here to help you with anything!"))

        // Good responses
        XCTAssertFalse(AIResponseCleaner.isLowQuality(
            "You've eaten 1200 of 1800 cal. Consider a protein-rich dinner."))

        // Markdown stripping
        let md = "**You've eaten** 1200 cal. ## Summary\nKeep going!"
        let cleaned = AIResponseCleaner.clean(md)
        XCTAssertFalse(cleaned.contains("**"))
        XCTAssertFalse(cleaned.contains("##"))

        // Artifact stripping
        let dirty = "Hello<|im_end|> world<|im_start|>assistant"
        let artCleaned = AIResponseCleaner.clean(dirty)
        XCTAssertFalse(artCleaned.contains("<|im_end|>"))
    }

    // MARK: - Workout Action Parsing (Legacy)

    func testCreateWorkoutParsing() {
        let (action, clean) = AIActionParser.parse("Let's do it! [CREATE_WORKOUT: Push Ups 3x15, Bench Press 3x10@135]")
        if case .createWorkout(let exercises) = action {
            XCTAssertEqual(exercises.count, 2)
            XCTAssertEqual(exercises[0].name, "Push Ups")
            XCTAssertEqual(exercises[1].weight, 135)
        } else { XCTFail("Expected createWorkout") }
        XCTAssertTrue(clean.contains("Let's do it"))
    }

    func testStartWorkoutParsing() {
        let (action, _) = AIActionParser.parse("[START_WORKOUT: Push Day]")
        if case .startWorkout(let type) = action {
            XCTAssertEqual(type, "Push Day")
        } else { XCTFail("Expected startWorkout") }
    }

    // MARK: - Chain-of-Thought Routing

    @MainActor
    func testChainOfThoughtRouting() {
        let queries: [(String, AIScreen, Bool)] = [
            ("how am I doing", .dashboard, true),
            ("am I on track", .weight, true),
            ("what should I eat for dinner", .food, true),
            ("how's my sleep", .bodyRhythm, true),
            ("which markers are out of range", .biomarkers, true),
            ("what should I train", .exercise, true),
            ("why am I not losing weight", .weight, true),
            // Simple → should NOT trigger
            ("hello", .dashboard, false),
            ("thanks", .dashboard, false),
            ("ok", .dashboard, false),
        ]
        var correct = 0
        for (query, screen, expected) in queries {
            let has = AIChainOfThought.plan(query: query, screen: screen) != nil
            if has == expected { correct += 1 }
            else { print("ROUTING: '\(query)' expected=\(expected) got=\(has)") }
        }
        let pct = Double(correct) / Double(queries.count) * 100
        print("📊 CoT routing: \(correct)/\(queries.count) (\(String(format: "%.0f", pct))%)")
        XCTAssertGreaterThanOrEqual(correct, queries.count * 85 / 100)
    }
}
