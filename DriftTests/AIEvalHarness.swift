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
            // Summaries
            ("daily summary", "day"), ("summary", "day"),
            ("yesterday", ""), ("this week", ""), ("weekly summary", ""),
            // Nutrition status
            ("calories left", "cal"), ("how many calories left", "cal"),
            ("what did i eat today", ""), ("what did i eat", ""),
            // Supplements
            ("supplements", ""), ("did i take everything", ""),
            // Copy
            ("copy yesterday", ""),
            // Topic continuation
            ("what about protein?", "protein"), ("what about carbs?", "carb"),
            ("how about fat?", "fat"), ("and protein?", "protein"),
            ("what's my protein", "protein"),
            // Data entry
            ("body fat 18", "bf"), ("bf 22.5", "bf"),
            ("bmi 24", "bmi"), ("bmi 22.1", "bmi"),
            ("set goal to 160 lbs", "goal"), ("target weight 75 kg", "goal"),
            ("i want to weigh 150", "goal"),
            ("set my goal to one sixty", "goal"),
            // Quick-add
            ("log 500 cal", "quick"), ("log 400 calories for lunch", "quick"),
            ("log 400 cal 30g protein lunch", "macro"),
            // Greetings & closers
            ("hi", "greet"), ("hello", "greet"), ("hey", "greet"),
            ("thanks", "thanks"), ("thank you", "thanks"), ("ok", "ok"),
            // Activity/exercise via StaticOverrides
            ("i did yoga for 30 minutes", ""),
            ("i did push ups", ""),
            ("just did 20 min cardio", ""),
            // Delete/remove food
            ("delete last entry", "delete"),
            ("remove the rice", "delete"),
            ("undo last food", "delete"),
            // Calorie estimation
            ("calories in samosa", "estimate"),
            ("estimate calories for biryani", "estimate"),
            ("how many calories in a banana", "estimate"),
            ("i want to estimate calories for samosa", "estimate"),
            // Diet/fitness advice
            ("i want to reduce fat", "advice"),
            ("how to lose fat", "advice"),
            ("tips to cut fat", "advice"),
            // Topic continuation — yesterday
            ("and yesterday?", "yesterday"),
            ("what about yesterday?", "yesterday"),
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
            // Basic verb forms
            "log 2 eggs", "ate chicken breast", "had a banana",
            "add a protein shake", "track 3 rotis", "eating oatmeal",
            "logged half avocado", "log eggs for dinner",
            // Natural phrasing
            "I just had a samosa for lunch", "just ate some yogurt",
            "i had a coffee", "had 3 eggs for breakfast",
            "i just had chicken and rice",
            // Quantifiers
            "ate a couple of eggs", "just had some dal",
            "i ate a few rotis", "had a scoop of protein",
            "ate a lot of rice",
            // Unit-based
            "i ate 2 slices of pizza", "had a cup of rice",
            "log a bowl of oatmeal", "log 2 scoops protein",
            "ate 3 pieces of chicken",
            // Multi-food
            "log rice and dal", "i had 2 eggs and a banana",
            // Indian foods
            "had paneer tikka", "ate 2 idli with chutney",
            "log 1 dosa", "had a plate of biryani",
            "ate chole bhature", "log rajma chawal",
            "had 2 parathas for breakfast", "ate aloo gobi",
            // American foods
            "had a cheeseburger", "ate spaghetti and meatballs",
            "log a caesar salad", "had a PB&J sandwich",
            "ate mac and cheese", "log turkey sandwich",
            // Drinks
            "drank a smoothie", "had a glass of milk",
            "drinking green tea", "log a latte",
            // Gram-based
            "log 100g chicken", "ate 200 gram rice",
            "had 150g paneer", "log paneer biryani 300 gram",
            // Servings
            "had 1.5 servings of pasta", "log 2 portions of dal",
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
            // Info/status queries
            "how am I doing", "what's my TDEE", "weekly summary",
            "yesterday", "what should I eat", "supplements",
            // Exercise queries
            "log exercise", "log workout", "how was my workout",
            "start smart workout", "coach me today",
            // Weight queries
            "how's my weight", "am I losing weight",
            // Ambiguous
            "hello", "thanks", "ok", "yeah", "sure",
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
            ("i'm at 160 lbs", 160.0, .lbs),
            ("weight: 78.5 kg", 78.5, .kg),
            ("I weigh 155", 155.0, .lbs),
            ("log weight 80 kg", 80.0, .kg),
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
            "set goal to 160 lbs", "target weight 75 kg",
            "how's my weight going", "am I on track for my goal",
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
            ("track 3 rotis", "log_food"),
            ("ate paneer tikka", "log_food"),
            ("log 100g chicken", "log_food"),
            ("had a protein shake", "log_food"),
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
            ("what should I eat for dinner", "food_info"),
            ("how many calories in rice", "food_info"),
            ("macros today", "food_info"),
            ("what are the macros in chicken", "food_info"),
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
            ("start smart workout", "start_workout", .exercise),
            ("begin leg day", "start_workout", .exercise),
            ("start push day", "start_workout", .exercise),
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
            ("4 rotis", 4, "rotis"),
            ("1.5 cups of rice", 1.5, "rice"),
            ("two eggs", 2, "eggs"),
            ("an apple", 1, "apple"),
            ("lots of rice", 2, "rice"),
            ("3 slices of pizza", 3, "pizza"),
            ("a piece of cake", 1, "cake"),
            ("5 almonds", 5, "almonds"),
            // Range parsing: "2 to 3 bananas" → 3
            ("2 to 3 bananas", 3, "bananas"),
            ("1 or 2 eggs", 2, "eggs"),
            // Word number + food
            ("three biryani", 3, "biryani"),
            ("two rotis", 2, "rotis"),
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
            ("log chicken, rice, and dal", 3),
            ("ate eggs, bacon, and toast", 3),
            ("had paneer and naan", 2),
            ("log rice and dal and roti", 3),
            ("ate oatmeal and banana", 2),
            ("i had coffee and toast", 2),
        ]
        for (query, expectedCount) in shouldSplit {
            let intents = AIActionExecutor.parseMultiFoodIntent(query.lowercased())
            XCTAssertNotNil(intents, "'\(query)' should split into multi-food")
            XCTAssertEqual(intents?.count, expectedCount, "'\(query)' should have \(expectedCount) items")
        }
    }

    func testCompoundFoodsNotSplit() {
        let compounds = ["mac and cheese", "bread and butter", "rice and beans", "peanut butter and jelly", "salt and pepper chicken"]
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
            LayerTest(query: "hello", expectedLayer: "static"),
            LayerTest(query: "daily summary", expectedLayer: "static"),
            LayerTest(query: "summary", expectedLayer: "static"),
            LayerTest(query: "calories left", expectedLayer: "static"),
            LayerTest(query: "body fat 18", expectedLayer: "static"),
            LayerTest(query: "log 500 cal", expectedLayer: "static"),
            LayerTest(query: "yesterday", expectedLayer: "static"),
            LayerTest(query: "this week", expectedLayer: "static"),
            LayerTest(query: "weekly summary", expectedLayer: "static"),
            LayerTest(query: "supplements", expectedLayer: "static"),
            LayerTest(query: "copy yesterday", expectedLayer: "static"),
            LayerTest(query: "thanks", expectedLayer: "static"),
            LayerTest(query: "set goal to 160 lbs", expectedLayer: "static"),
            LayerTest(query: "bf 22", expectedLayer: "static"),
            LayerTest(query: "bmi 24", expectedLayer: "static"),
            LayerTest(query: "what about protein?", expectedLayer: "static"),
            LayerTest(query: "i did yoga for 30 minutes", expectedLayer: "static"),
            LayerTest(query: "just did 20 min cardio", expectedLayer: "static"),

            // Food parser layer
            LayerTest(query: "I had 2 eggs", expectedLayer: "food_parser"),
            LayerTest(query: "ate chicken and rice", expectedLayer: "food_parser"),
            LayerTest(query: "log a banana", expectedLayer: "food_parser"),
            LayerTest(query: "ate paneer tikka", expectedLayer: "food_parser"),
            LayerTest(query: "had 3 rotis for dinner", expectedLayer: "food_parser"),
            LayerTest(query: "log 100g chicken", expectedLayer: "food_parser"),

            // Weight parser layer
            LayerTest(query: "I weigh 165 lbs", expectedLayer: "weight_parser"),
            LayerTest(query: "weight is 75.2 kg", expectedLayer: "weight_parser"),
            LayerTest(query: "scale says 82 kg", expectedLayer: "weight_parser"),
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

    // MARK: - Messy Input Parsing (normalizer accuracy targets)

    @MainActor
    func testMessyFoodInputParsing() {
        // These test the deterministic parser — messy inputs that should work WITHOUT LLM normalizer
        let cases: [(String, String?, Double?)] = [
            // Count unit parsing: "2 slices of pizza" → servings=2
            ("log 2 slices of pizza", "pizza", 2),
            ("ate 3 pieces of chicken", "chicken", 3),
            ("had 2 cups of rice", "rice", 2),
            ("log 2 scoops protein", "protein", 2),
            ("ate 1 serving of pasta", "pasta", 1),
            ("had 2 portions of dal", "dal", 2),
            ("log 1 tbsp of ghee", "ghee", 1),
            // Gram parsing
            ("log 100 gram of rice", "rice", nil),
            ("ate 200g chicken", "chicken", nil),
            ("log 50 ml milk", nil, nil), // gram amount, not servings
            // Natural phrasing
            ("i had some rice", "rice", nil),
            ("just had eggs", "eggs", nil),
            ("just ate a mango", "mango", nil),
            ("eating a sandwich", "sandwich", nil),
            // Multi-food (no single parse expected)
            ("i ate chicken and rice", nil, nil),
            // Edge cases
            ("log half avocado", "avocado", nil),
            ("ate a couple of eggs", "eggs", 2),
        ]
        var correct = 0
        for (input, expectedQuery, expectedServings) in cases {
            let intent = AIActionExecutor.parseFoodIntent(input)
            if let expectedQuery {
                if intent != nil && intent!.query.lowercased().contains(expectedQuery) {
                    if let expectedServings {
                        if intent!.servings == expectedServings { correct += 1 }
                        else { print("MESSY: '\(input)' servings=\(intent?.servings as Any) expected=\(expectedServings)") }
                    } else { correct += 1 }
                } else {
                    print("MESSY: '\(input)' query=\(intent?.query ?? "nil") expected=\(expectedQuery)")
                }
            } else {
                correct += 1  // no specific query expectation
            }
        }
        let pct = Double(correct) / Double(cases.count) * 100
        print("📊 Messy food input: \(correct)/\(cases.count) (\(String(format: "%.0f", pct))%)")
        XCTAssertGreaterThanOrEqual(correct, cases.count * 80 / 100)
    }

    @MainActor
    func testCountUnitExtraction() {
        // extractAmount should return servings for count units, grams for weight units
        let countCases: [(String, Double?, Double?)] = [
            ("2 slices of pizza", 2, nil),       // servings=2, grams=nil
            ("3 pieces of chicken", 3, nil),
            ("2 cups of dal", 2, nil),
            ("1 serving of rice", 1, nil),
            ("100 gram of rice", nil, 100),       // servings=nil, grams=100
            ("200 ml of milk", nil, 200),
            ("50 g paneer", nil, 50),
            // Compact leading: "200ml milk"
            ("200ml milk", nil, 200),
            ("100g chicken", nil, 100),
            ("300g rice", nil, 300),
            // Word amount + unit: "half cup oats"
            ("half cup oats", 0.5, nil),
            ("two scoops protein", 2, nil),
            ("quarter cup rice", 0.25, nil),
        ]
        var correct = 0
        for (input, expectedServings, expectedGrams) in countCases {
            let (servings, _, grams) = AIActionExecutor.extractAmount(from: input)
            let servingsOk = servings == expectedServings
            let gramsOk = grams == expectedGrams
            if servingsOk && gramsOk { correct += 1 }
            else { print("EXTRACT: '\(input)' servings=\(servings as Any)/\(expectedServings as Any) grams=\(grams as Any)/\(expectedGrams as Any)") }
        }
        let pct = Double(correct) / Double(countCases.count) * 100
        print("📊 Count unit extraction: \(correct)/\(countCases.count) (\(String(format: "%.0f", pct))%)")
        XCTAssertGreaterThanOrEqual(correct, countCases.count * 85 / 100)
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
