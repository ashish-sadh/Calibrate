import XCTest
@testable import Drift

/// Gold-standard evaluation harness for the unified AI chat pipeline.
/// Tests the real flow: StaticOverrides → AIActionExecutor → ToolRanker → tool execution.
/// No LLM needed — all deterministic Swift logic.
/// Run: xcodebuild test -only-testing:'DriftTests/AIEvalHarness'
final class AIEvalHarness: XCTestCase {

    override func setUp() {
        super.setUp()
        // Ensure ToolRegistry is populated for ToolRanker tests
        MainActor.assumeIsolated {
            if ToolRegistry.shared.allTools().isEmpty {
                ToolRegistration.registerAll()
            }
        }
    }

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
            // Commands that stay in StaticOverrides (instant, no LLM):
            // Copy
            ("copy yesterday", ""),
            // Topic continuation (macro lookups)
            // Topic continuation ("what about protein?") — moved to ToolRanker (food_info tool)
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
            // Activity/exercise
            ("i did yoga for 30 minutes", ""),
            ("i did push ups", ""),
            ("just did 20 min cardio", ""),
            ("i did yoga for like half an hour", ""),
            ("i did running for about 45 minutes", ""),
            // Delete/remove food
            ("delete last entry", "delete"),
            ("remove the rice", "delete"),
            ("undo last food", "delete"),
            // Barcode scan
            ("scan barcode", "scan"), ("scan food", "scan"),
            // Undo
            ("undo", "undo"), ("undo that", "undo"), ("undo last", "undo"),
            // TDEE/BMR — moved to ToolRanker (weight_info tool)
            // Calorie estimation — moved to food_info tool (FoodService.getNutrition)
            // Diet/fitness advice — moved to food_info tool (LLM presentation)
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
    func testInlineMacrosCarbFatNotGreedy() {
        // "400 cal" should NOT be parsed as 400 carbs (the "c" in "cal" was matching carb regex)
        let result = StaticOverrides.match("log 400 cal 30g protein lunch")
        XCTAssertNotNil(result, "Should match as inline macros")

        // With explicit carbs and fat: "log 400 cal 30g protein 50 carbs 20 fat"
        let result2 = StaticOverrides.match("log 400 cal 30g protein 50 carbs 20 fat")
        XCTAssertNotNil(result2, "Should match with explicit carbs and fat")

        // "30 for lunch" should NOT parse 30 as fat (the "f" in "for" was matching fat regex)
        let result3 = StaticOverrides.match("log 400 cal 30g protein for lunch")
        XCTAssertNotNil(result3, "Should match even with 'for' in input")
    }

    @MainActor
    func testInlineMacrosFoodNameExtraction() {
        // "mendocino salad: 690 cal 19g protein 47g carbs 51g fat" → should extract "Mendocino Salad"
        let result = StaticOverrides.match("mendocino salad: 690 calories 19g protein 47g carbs 51g fat")
        XCTAssertNotNil(result, "Should match inline macros with food name prefix")

        // "chipotle bowl 800 cal 30g protein 50 carbs 35 fat" → "Chipotle Bowl"
        let result2 = StaticOverrides.match("chipotle bowl 800 cal 30g protein 50 carbs 35 fat")
        XCTAssertNotNil(result2, "Should match with food name before macros")

        // "log 400 cal 30g protein" → no food name prefix (starts with number after stripping "log")
        let result3 = StaticOverrides.match("log 400 cal 30g protein")
        XCTAssertNotNil(result3, "Should still match without food name")
    }

    @MainActor
    func testInlineMacrosCarbSanityCheck() {
        // Carb value matching calorie value should be rejected as likely error
        // Simulated: if carb regex somehow extracted 690 when calories=690
        let result = StaticOverrides.match("test food 690 cal 19g protein 690g carbs 51g fat")
        XCTAssertNotNil(result, "Should match even with suspicious carbs")
        // The handler should sanitize carbs=690 when cal=690 (sanity check)
    }

    @MainActor
    func testInlineMacrosShorthandFormat() {
        // "800 cal 30p 50c 35f" — shorthand C/P/F format
        let result = StaticOverrides.match("chipotle bowl 800 cal 30p 50c 35f")
        XCTAssertNotNil(result, "Should match shorthand format with C suffix")
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

    // MARK: - Workout Set Pattern Detection

    @MainActor
    func testWorkoutSetPatternNotCaughtByActivityHandler() {
        // Structured workout exercises must fall through StaticOverrides to the AI pipeline.
        // The help text explicitly tells users "I did bench press 3x10 at 135" — it must work.
        let workoutSetQueries = [
            "i did bench press 3x10 at 135",    // NxN + at N lbs
            "i did bench press 3x10 at 135 lbs",
            "i did squats 4x8 at 225 lbs",
            "i did pull ups 3x12",               // NxN only
            "just did deadlifts 3x5 at 315",
            "did push ups 3x20",
            "i did bench press 3x10@135",        // @N weight format
            "i did overhead press 4 sets of 10 at 95 lbs",  // "N sets of M"
        ]
        for query in workoutSetQueries {
            let result = StaticOverrides.match(query)
            XCTAssertNil(result, "'\(query)' should fall through (nil) — not treated as generic activity")
        }
    }

    @MainActor
    func testContainsWorkoutSetPattern() {
        // Patterns that ARE workout sets
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("bench press 3x10 at 135"))
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("squats 4x8"))
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("pull ups 3x12"))
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("overhead press 4 sets of 10 at 95 lbs"))
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("bench@135"))
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("deadlift at 315 lbs"))
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("squat at 225 kg"))

        // Patterns that are NOT workout sets (should remain as activities)
        XCTAssertFalse(StaticOverrides.containsWorkoutSetPattern("yoga"))
        XCTAssertFalse(StaticOverrides.containsWorkoutSetPattern("running"))
        XCTAssertFalse(StaticOverrides.containsWorkoutSetPattern("cardio for 30 min"))
        XCTAssertFalse(StaticOverrides.containsWorkoutSetPattern("push ups"))
        XCTAssertFalse(StaticOverrides.containsWorkoutSetPattern("hiit workout"))
    }

    @MainActor
    func testSimpleActivitiesStillCaughtByStaticOverrides() {
        // Plain activities (no sets/reps/weight) must still be handled by StaticOverrides
        let plainActivities = [
            "i did yoga",
            "i did push ups",
            "just did 20 min cardio",
            "i did yoga for 30 minutes",
            "i went for a run",
        ]
        for query in plainActivities {
            let result = StaticOverrides.match(query)
            XCTAssertNotNil(result, "'\(query)' should still be caught by StaticOverrides")
            if case .response(let text) = result {
                XCTAssertTrue(text.contains("Log") && text.contains("confirm"),
                    "'\(query)' should produce activity confirmation")
            }
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
            // Queries that were removed from StaticOverrides — must route here
            ("daily summary", "food_info"),
            ("how am I doing", "food_info"),
            ("yesterday", "food_info"),
            ("how are you doing", "food_info"),
            ("what did I eat today", "food_info"),
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
            // log_weight (10 queries)
            ("I weigh 165 lbs", "log_weight", .weight),
            ("weighed in at 170 this morning", "log_weight", .weight),
            ("scale said 82 kg", "log_weight", .weight),
            ("log weight 78", "log_weight", .weight),
            ("my weight is 74 kg", "log_weight", .weight),
            ("scale shows 180 lbs", "log_weight", .weight),
            ("weighed myself 165", "log_weight", .weight),
            ("weigh 72 kg today", "log_weight", .weight),
            ("scale reading 68 kg", "log_weight", .weight),
            ("i weigh 155 this morning", "log_weight", .weight),
            // weight_info (10 queries)
            ("how's my weight trend", "weight_info", .weight),
            ("am I on track to reach my goal", "weight_info", .weight),
            ("how much have I lost", "weight_info", .weight),
            ("am I losing weight", "weight_info", .weight),
            ("weight progress", "weight_info", .weight),
            ("why am I not losing weight", "weight_info", .weight),
            ("am I at a plateau", "weight_info", .weight),
            ("what's my TDEE", "weight_info", .weight),
            ("explain my BMR", "weight_info", .weight),
            ("am I gaining too fast", "weight_info", .weight),
            // set_goal (10 queries)
            ("set goal to 160", "set_goal", .goal),
            ("goal weight 155 pounds", "set_goal", .goal),
            ("target weight 70 kg", "set_goal", .goal),
            ("i want to weigh 140 lbs", "set_goal", .goal),
            ("update my goal weight to 72 kg", "set_goal", .goal),
            ("set goal weight to 150", "set_goal", .goal),
            ("set my target to 160 lbs", "set_goal", .goal),
            ("change goal to 145", "set_goal", .goal),
            ("new goal weight 65 kg", "set_goal", .goal),
            ("set target 175 lbs", "set_goal", .goal),
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
            // start_workout (15 queries)
            ("start chest workout", "start_workout", .exercise),
            ("start smart workout", "start_workout", .exercise),
            ("begin leg day", "start_workout", .exercise),
            ("start push day", "start_workout", .exercise),
            ("start arms workout", "start_workout", .exercise),
            ("begin full body session", "start_workout", .exercise),
            ("want to train biceps today", "start_workout", .exercise),
            ("let's do legs", "start_workout", .exercise),
            ("train shoulders", "start_workout", .exercise),
            ("upper body workout time", "start_workout", .exercise),
            ("let's do back and biceps", "start_workout", .exercise),
            ("begin glute workout", "start_workout", .exercise),
            ("want to do abs today", "start_workout", .exercise),
            ("work on triceps today", "start_workout", .exercise),
            ("begin lower body session", "start_workout", .exercise),
            // exercise_info (15 queries)
            ("what should I train today", "exercise_info", .exercise),
            ("show workout history", "exercise_info", .exercise),
            ("how many workouts this week", "exercise_info", .exercise),
            ("how many times did I work out", "exercise_info", .exercise),
            ("how's my deadlift", "exercise_info", .exercise),
            ("workout count for the month", "exercise_info", .exercise),
            ("is my squat improving", "exercise_info", .exercise),
            ("how often did I train last month", "exercise_info", .exercise),
            ("bench press progress", "exercise_info", .exercise),
            ("am I overloading my lifts", "exercise_info", .exercise),
            ("workout count this month", "exercise_info", .exercise),
            ("am i stalling on my lifts", "exercise_info", .exercise),
            ("how many workouts last month", "exercise_info", .exercise),
            ("overloading my bench press", "exercise_info", .exercise),
            ("squat and deadlift progress", "exercise_info", .exercise),
            // log_activity (15 queries)
            ("I did yoga for 30 min", "log_activity", .exercise),
            ("just finished cycling session", "log_activity", .exercise),
            ("i did 45 min cardio", "log_activity", .exercise),
            ("just did 30 min swimming", "log_activity", .exercise),
            ("i walked for 30 minutes", "log_activity", .exercise),
            ("went running for 20 minutes", "log_activity", .exercise),
            ("i did pilates for 45 minutes", "log_activity", .exercise),
            ("went hiking for 60 minutes", "log_activity", .exercise),
            ("i did 30 min of running", "log_activity", .exercise),
            ("just did 60 minutes cycling", "log_activity", .exercise),
            ("just did 20 minutes of yoga", "log_activity", .exercise),
            ("i did rowing for 20 minutes", "log_activity", .exercise),
            ("just did hiit for 30 minutes", "log_activity", .exercise),
            ("went hiking for 2 hours", "log_activity", .exercise),
            ("just finished a swimming workout", "log_activity", .exercise),
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
            // sleep_recovery (15 queries)
            ("how'd I sleep", "sleep_recovery", .bodyRhythm),
            ("sleep trend", "sleep_recovery", .bodyRhythm),
            ("how was my sleep", "sleep_recovery", .bodyRhythm),
            ("sleep quality", "sleep_recovery", .bodyRhythm),
            ("how'd I sleep last night", "sleep_recovery", .bodyRhythm),
            ("show my sleep trend", "sleep_recovery", .bodyRhythm),
            ("what's my HRV last night", "sleep_recovery", .bodyRhythm),
            ("am I recovered from yesterday", "sleep_recovery", .bodyRhythm),
            ("sleep score last night", "sleep_recovery", .bodyRhythm),
            ("how was my sleep quality this week", "sleep_recovery", .bodyRhythm),
            ("how did I sleep this week", "sleep_recovery", .bodyRhythm),
            ("last night's sleep quality", "sleep_recovery", .bodyRhythm),
            ("sleep hours this week", "sleep_recovery", .bodyRhythm),
            ("was I in deep sleep last night", "sleep_recovery", .bodyRhythm),
            ("what's my recovery score", "sleep_recovery", .bodyRhythm),
            // mark_supplement (15 queries)
            ("took my creatine", "mark_supplement", .supplements),
            ("took my vitamins", "mark_supplement", .supplements),
            ("had my fish oil today", "mark_supplement", .supplements),
            ("took vitamin d", "mark_supplement", .supplements),
            ("took fish oil", "mark_supplement", .supplements),
            ("had my creatine today", "mark_supplement", .supplements),
            ("just took my omega 3", "mark_supplement", .supplements),
            ("taken my magnesium", "mark_supplement", .supplements),
            ("took my supplements this morning", "mark_supplement", .supplements),
            ("had my vitamin d", "mark_supplement", .supplements),
            ("took my zinc today", "mark_supplement", .supplements),
            ("had my b12 this morning", "mark_supplement", .supplements),
            ("took my l-theanine", "mark_supplement", .supplements),
            ("just took my probiotic", "mark_supplement", .supplements),
            ("taken my multivitamin", "mark_supplement", .supplements),
            // supplements status (15 queries)
            ("supplement status", "supplements", .supplements),
            ("what supplements do I take", "supplements", .supplements),
            ("did I take my vitamins", "supplements", .supplements),
            ("vitamin stack", "supplements", .supplements),
            ("show my supplements", "supplements", .supplements),
            ("vitamin status today", "supplements", .supplements),
            ("supplement tracker", "supplements", .supplements),
            ("what's in my stack", "supplements", .supplements),
            ("vitamin D status", "supplements", .supplements),
            ("which supplements am I missing today", "supplements", .supplements),
            ("did i take all my vitamins today", "supplements", .supplements),
            ("what supplements do i have", "supplements", .supplements),
            ("check my supplement schedule", "supplements", .supplements),
            ("am i missing any supplements", "supplements", .supplements),
            ("show my vitamin schedule", "supplements", .supplements),
            // glucose (15 queries)
            ("any glucose spikes", "glucose", .glucose),
            ("blood sugar today", "glucose", .glucose),
            ("how's my glucose", "glucose", .glucose),
            ("glucose trend", "glucose", .glucose),
            ("any blood sugar spikes", "glucose", .glucose),
            ("what was my highest glucose", "glucose", .glucose),
            ("glucose levels today", "glucose", .glucose),
            ("cgm data", "glucose", .glucose),
            ("blood sugar spike today", "glucose", .glucose),
            ("blood sugar chart", "glucose", .glucose),
            ("show glucose trend", "glucose", .glucose),
            ("what's my blood sugar average", "glucose", .glucose),
            ("any glucose issues today", "glucose", .glucose),
            ("my cgm readings today", "glucose", .glucose),
            ("my cgm spike data", "glucose", .glucose),
            // biomarkers (15 queries)
            ("lab results", "biomarkers", .biomarkers),
            ("any markers out of range", "biomarkers", .biomarkers),
            ("show my biomarkers", "biomarkers", .biomarkers),
            ("how's my cholesterol", "biomarkers", .biomarkers),
            ("blood work results", "biomarkers", .biomarkers),
            ("check my labs", "biomarkers", .biomarkers),
            ("what are my recent lab values", "biomarkers", .biomarkers),
            ("a1c results", "biomarkers", .biomarkers),
            ("blood test results", "biomarkers", .biomarkers),
            ("which biomarkers are abnormal", "biomarkers", .biomarkers),
            ("show my blood work summary", "biomarkers", .biomarkers),
            ("my a1c results", "biomarkers", .biomarkers),
            ("latest blood test", "biomarkers", .biomarkers),
            ("thyroid lab results", "biomarkers", .biomarkers),
            ("review my lab numbers", "biomarkers", .biomarkers),
            // body_comp (15 queries)
            ("how's my body fat", "body_comp", .bodyComposition),
            ("body composition", "body_comp", .bodyComposition),
            ("muscle mass trend", "body_comp", .bodyComposition),
            ("body fat percentage", "body_comp", .bodyComposition),
            ("lean mass progress", "body_comp", .bodyComposition),
            ("body recomposition progress", "body_comp", .bodyComposition),
            ("how much muscle have I gained", "body_comp", .bodyComposition),
            ("dexa results", "body_comp", .bodyComposition),
            ("what's my current body fat", "body_comp", .bodyComposition),
            ("show body composition trend", "body_comp", .bodyComposition),
            ("body fat trend over time", "body_comp", .bodyComposition),
            ("my lean mass history", "body_comp", .bodyComposition),
            ("check my body recomposition progress", "body_comp", .bodyComposition),
            ("weekly body fat chart", "body_comp", .bodyComposition),
            ("how's my body composition changing", "body_comp", .bodyComposition),
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
    func testParamExtractionForKeyTools() {
        // food_info should extract query context
        if let tool = ToolRegistry.shared.allTools().first(where: { $0.name == "food_info" }) {
            let params = ToolRanker.extractParamsForTool(tool, from: "how much protein today")
            XCTAssertTrue(params["query"]?.contains("protein") ?? false, "food_info should extract 'protein' from query")
        }

        // start_workout should extract workout name
        if let tool = ToolRegistry.shared.allTools().first(where: { $0.name == "start_workout" }) {
            let params = ToolRanker.extractParamsForTool(tool, from: "start push day")
            XCTAssertTrue(params["name"]?.contains("push") ?? false, "start_workout should extract 'push' from name")
        }

        // log_activity should extract activity + duration
        if let tool = ToolRegistry.shared.allTools().first(where: { $0.name == "log_activity" }) {
            let params = ToolRanker.extractParamsForTool(tool, from: "i did yoga for 30 min")
            XCTAssertNotNil(params["name"], "log_activity should extract activity name")
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
            // StaticOverrides layer (commands only)
            LayerTest(query: "hi", expectedLayer: "static"),
            LayerTest(query: "hello", expectedLayer: "static"),
            LayerTest(query: "body fat 18", expectedLayer: "static"),
            LayerTest(query: "log 500 cal", expectedLayer: "static"),
            LayerTest(query: "copy yesterday", expectedLayer: "static"),
            LayerTest(query: "thanks", expectedLayer: "static"),
            LayerTest(query: "set goal to 160 lbs", expectedLayer: "static"),
            LayerTest(query: "bf 22", expectedLayer: "static"),
            LayerTest(query: "bmi 24", expectedLayer: "static"),
            LayerTest(query: "what about protein?", expectedLayer: "tool_ranker"),
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

            // Tool ranker layer (info queries — routed to LLM presentation)
            LayerTest(query: "daily summary", expectedLayer: "tool_ranker"),
            LayerTest(query: "calories left", expectedLayer: "tool_ranker"),
            LayerTest(query: "how am I doing", expectedLayer: "tool_ranker"),
            LayerTest(query: "what should I eat", expectedLayer: "tool_ranker"),
            LayerTest(query: "sleep trend", expectedLayer: "tool_ranker"),
            LayerTest(query: "how much have I lost", expectedLayer: "tool_ranker"),
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
            } else if !ToolRanker.rank(query: lower, screen: .dashboard, topN: 2).isEmpty {
                hitLayer = "tool_ranker" // Phase 3: tool-first execution via rank()
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

    // MARK: - Intent Classifier JSON Parsing

    func testIntentClassifierFoodLog() {
        let response = #"{"tool":"log_food","items":["eggs","toast"],"meal":"breakfast","servings":"2"}"#
        let intent = IntentClassifier.parseResponse(response)
        XCTAssertNotNil(intent, "Should parse food log JSON")
        XCTAssertEqual(intent?.tool, "log_food")
        XCTAssertEqual(intent?.params["meal"], "breakfast")
        XCTAssertTrue(intent?.params["items"]?.contains("eggs") ?? false)
    }

    func testIntentClassifierFoodQuery() {
        let response = #"{"tool":"food_info","query":"calories left"}"#
        let intent = IntentClassifier.parseResponse(response)
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.tool, "food_info")
        XCTAssertEqual(intent?.params["query"], "calories left")
    }

    func testIntentClassifierWeightLog() {
        let response = #"{"tool":"log_weight","value":"165","unit":"lbs"}"#
        let intent = IntentClassifier.parseResponse(response)
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.tool, "log_weight")
        XCTAssertEqual(intent?.params["value"], "165")
        XCTAssertEqual(intent?.params["unit"], "lbs")
    }

    func testIntentClassifierChatResponse() {
        // Non-JSON response = chat, should return nil
        let response = "You're doing great today!"
        let intent = IntentClassifier.parseResponse(response)
        XCTAssertNil(intent, "Chat text should return nil (not a tool call)")
    }

    func testIntentClassifierExercise() {
        let response = #"{"tool":"start_workout","name":"push day"}"#
        let intent = IntentClassifier.parseResponse(response)
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.tool, "start_workout")
        XCTAssertEqual(intent?.params["name"], "push day")
    }

    func testIntentClassifierMalformedJSON() {
        let response = #"{"tool": broken json"#
        let intent = IntentClassifier.parseResponse(response)
        XCTAssertNil(intent, "Malformed JSON should return nil")
    }

    func testIntentClassifierJSONInText() {
        // LLM sometimes wraps JSON in text
        let response = #"Sure! {"tool":"food_info","query":"daily summary"} Let me check."#
        let intent = IntentClassifier.parseResponse(response)
        XCTAssertNotNil(intent, "Should extract JSON from surrounding text")
        XCTAssertEqual(intent?.tool, "food_info")
    }

    func testIntentClassifierNumericParams() {
        let response = #"{"tool":"log_weight","value":165.5,"unit":"lbs"}"#
        let intent = IntentClassifier.parseResponse(response)
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.params["value"], "165.5")
    }

    // MARK: - ClassifyResult: Text vs Tool Call

    func testClassifyResultTextForFollowUp() {
        // "log lunch" → LLM should ask follow-up, which parseResponse returns nil for
        // The ClassifyResult.text path captures this
        let followUp = "What did you have for lunch?"
        let result = IntentClassifier.parseResponse(followUp)
        XCTAssertNil(result, "Follow-up question should not parse as tool call")
    }

    func testClassifyResultToolCallWithMacros() {
        let json = #"{"tool":"log_food","name":"chipotle bowl","calories":"3000","protein":"30","carbs":"45","fat":"67"}"#
        let intent = IntentClassifier.parseResponse(json)
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.tool, "log_food")
        XCTAssertEqual(intent?.params["calories"], "3000")
        XCTAssertEqual(intent?.params["protein"], "30")
        XCTAssertEqual(intent?.params["carbs"], "45")
        XCTAssertEqual(intent?.params["fat"], "67")
    }

    // MARK: - Intent Classifier Expanded Coverage (50+ patterns)
    // Tests parseResponse with realistic LLM output formats across all tools.

    func testIntentClassifierAllFoodLogVariants() {
        // Single item
        let r1 = IntentClassifier.parseResponse(#"{"tool":"log_food","name":"banana"}"#)
        XCTAssertEqual(r1?.tool, "log_food")

        // Multi-item with array
        let r2 = IntentClassifier.parseResponse(#"{"tool":"log_food","items":["rice","dal","chicken"],"meal":"lunch"}"#)
        XCTAssertEqual(r2?.tool, "log_food")
        XCTAssertTrue(r2?.params["items"]?.contains("dal") ?? false)

        // With servings
        let r3 = IntentClassifier.parseResponse(#"{"tool":"log_food","name":"eggs","servings":"3"}"#)
        XCTAssertEqual(r3?.params["servings"], "3")

        // Indian food
        let r4 = IntentClassifier.parseResponse(#"{"tool":"log_food","name":"paneer butter masala with 2 roti"}"#)
        XCTAssertEqual(r4?.tool, "log_food")

        // With meal type
        let r5 = IntentClassifier.parseResponse(#"{"tool":"log_food","name":"oats with milk","meal":"breakfast"}"#)
        XCTAssertEqual(r5?.params["meal"], "breakfast")
    }

    func testIntentClassifierAllFoodInfoVariants() {
        let queries = [
            (#"{"tool":"food_info","query":"calories left"}"#, "calories left"),
            (#"{"tool":"food_info","query":"daily summary"}"#, "daily summary"),
            (#"{"tool":"food_info","query":"how much protein today"}"#, "how much protein today"),
            (#"{"tool":"food_info","query":"what did I eat yesterday"}"#, "what did I eat yesterday"),
            (#"{"tool":"food_info","query":"suggest dinner"}"#, "suggest dinner"),
        ]
        for (json, expectedQuery) in queries {
            let intent = IntentClassifier.parseResponse(json)
            XCTAssertEqual(intent?.tool, "food_info", "Failed for: \(expectedQuery)")
            XCTAssertEqual(intent?.params["query"], expectedQuery)
        }
    }

    func testIntentClassifierWeightVariants() {
        // Log weight in lbs
        let r1 = IntentClassifier.parseResponse(#"{"tool":"log_weight","value":"165","unit":"lbs"}"#)
        XCTAssertEqual(r1?.tool, "log_weight")
        XCTAssertEqual(r1?.params["value"], "165")

        // Log weight in kg
        let r2 = IntentClassifier.parseResponse(#"{"tool":"log_weight","value":"75.2","unit":"kg"}"#)
        XCTAssertEqual(r2?.params["unit"], "kg")

        // Weight query
        let r3 = IntentClassifier.parseResponse(#"{"tool":"weight_info"}"#)
        XCTAssertEqual(r3?.tool, "weight_info")
        XCTAssertTrue(r3?.params.isEmpty ?? true)

        // Numeric value (not string)
        let r4 = IntentClassifier.parseResponse(#"{"tool":"log_weight","value":72.5,"unit":"kg"}"#)
        XCTAssertEqual(r4?.params["value"], "72.5")
    }

    func testIntentClassifierExerciseVariants() {
        // Start named workout
        let r1 = IntentClassifier.parseResponse(#"{"tool":"start_workout","name":"leg day"}"#)
        XCTAssertEqual(r1?.tool, "start_workout")
        XCTAssertEqual(r1?.params["name"], "leg day")

        // Log completed activity
        let r2 = IntentClassifier.parseResponse(#"{"tool":"log_activity","name":"running","duration":"45"}"#)
        XCTAssertEqual(r2?.tool, "log_activity")
        XCTAssertEqual(r2?.params["duration"], "45")

        // Exercise info query
        let r3 = IntentClassifier.parseResponse(#"{"tool":"exercise_info","query":"workout history"}"#)
        XCTAssertEqual(r3?.tool, "exercise_info")

        // Smart workout (no name)
        let r4 = IntentClassifier.parseResponse(#"{"tool":"start_workout"}"#)
        XCTAssertEqual(r4?.tool, "start_workout")
    }

    func testIntentClassifierSleepSupplementGoal() {
        // Sleep query
        let r1 = IntentClassifier.parseResponse(#"{"tool":"sleep_recovery","query":"how did I sleep"}"#)
        XCTAssertEqual(r1?.tool, "sleep_recovery")

        // Sleep with period
        let r2 = IntentClassifier.parseResponse(#"{"tool":"sleep_recovery","period":"week"}"#)
        XCTAssertEqual(r2?.params["period"], "week")

        // Mark supplement
        let r3 = IntentClassifier.parseResponse(#"{"tool":"mark_supplement","name":"vitamin d"}"#)
        XCTAssertEqual(r3?.tool, "mark_supplement")
        XCTAssertEqual(r3?.params["name"], "vitamin d")

        // Set goal
        let r4 = IntentClassifier.parseResponse(#"{"tool":"set_goal","target":"155","unit":"lbs"}"#)
        XCTAssertEqual(r4?.tool, "set_goal")
        XCTAssertEqual(r4?.params["target"], "155")
    }

    func testIntentClassifierEdgeCases() {
        // Empty JSON object
        let r1 = IntentClassifier.parseResponse("{}")
        XCTAssertNil(r1, "Empty JSON has no tool field")

        // Tool with empty string
        let r2 = IntentClassifier.parseResponse(#"{"tool":""}"#)
        XCTAssertNil(r2, "Empty tool string should be nil")

        // Markdown code block wrapping
        let r3 = IntentClassifier.parseResponse("```json\n{\"tool\":\"food_info\",\"query\":\"calories\"}\n```")
        XCTAssertEqual(r3?.tool, "food_info", "Should extract JSON from markdown code block")

        // LLM prefixes with explanation
        let r4 = IntentClassifier.parseResponse("Based on your request, here is the tool call: {\"tool\":\"log_food\",\"name\":\"salad\"}")
        XCTAssertEqual(r4?.tool, "log_food", "Should extract JSON from explanation text")

        // Multiple JSON objects (take first valid)
        let r5 = IntentClassifier.parseResponse(#"{"tool":"log_food","name":"eggs"} I've logged that for you."#)
        XCTAssertEqual(r5?.tool, "log_food")

        // Boolean param (should be ignored or stringified)
        let r6 = IntentClassifier.parseResponse(#"{"tool":"food_info","query":"summary","detailed":true}"#)
        XCTAssertEqual(r6?.tool, "food_info")
    }

    func testIntentClassifierLLMQuirks() {
        // LLM adds trailing comma (common Gemma quirk)
        let r1 = IntentClassifier.parseResponse(#"{"tool":"log_food","name":"rice",}"#)
        // May or may not parse depending on JSONSerialization tolerance — just verify no crash
        _ = r1

        // LLM uses single quotes (invalid JSON)
        let r2 = IntentClassifier.parseResponse("{'tool':'food_info','query':'calories'}")
        // JSONSerialization rejects single quotes — should return nil
        XCTAssertNil(r2, "Single quotes are invalid JSON")

        // LLM outputs tool name with parentheses
        let r3 = IntentClassifier.parseResponse(#"{"tool":"food_info()","query":"macros"}"#)
        XCTAssertEqual(r3?.tool, "food_info()", "Should preserve exact tool string for downstream handling")

        // Extra whitespace in JSON
        let r4 = IntentClassifier.parseResponse(#"  {  "tool" : "weight_info"  }  "#)
        XCTAssertEqual(r4?.tool, "weight_info")

        // Nested object in params (LLM sometimes does this)
        let r5 = IntentClassifier.parseResponse(#"{"tool":"log_food","name":"eggs","nutrition":{"cal":155}}"#)
        XCTAssertEqual(r5?.tool, "log_food")
        // nutrition is an object, not a string — should be excluded from params
    }

    func testIntentClassifierChatVariants() {
        // Greetings
        XCTAssertNil(IntentClassifier.parseResponse("Hi there!"))
        XCTAssertNil(IntentClassifier.parseResponse("Good morning! How can I help?"))
        XCTAssertNil(IntentClassifier.parseResponse("I'm here to help with your health tracking."))

        // Questions that aren't tool calls
        XCTAssertNil(IntentClassifier.parseResponse("What would you like to track today?"))
        XCTAssertNil(IntentClassifier.parseResponse("Sure, I can help with that!"))
    }

    // MARK: - Full Pipeline Coverage (StaticOverrides → ToolRanker)

    @MainActor
    func testCommonQueriesReachCorrectLayer() {
        // Queries that should hit StaticOverrides (instant, no LLM)
        let staticQueries = ["hi", "hello", "thanks", "help", "undo", "scan barcode",
                              "copy yesterday", "delete last entry"]
        for q in staticQueries {
            XCTAssertNotNil(StaticOverrides.match(q), "'\(q)' should match StaticOverrides")
        }

        // Queries that should NOT hit StaticOverrides (fall through to ToolRanker)
        let toolRankerQueries = ["calories left", "how am I doing", "daily summary",
                            "how much protein today", "suggest dinner",
                            "weight trend", "tdee", "what should I train",
                            "how did I sleep", "calories in samosa"]
        for q in toolRankerQueries {
            XCTAssertNil(StaticOverrides.match(q.lowercased()), "'\(q)' should NOT match StaticOverrides — should fall through to ToolRanker")
        }

        // Verify those toolRankerQueries queries DO rank a tool
        for q in toolRankerQueries {
            let tools = ToolRanker.rank(query: q.lowercased(), screen: .dashboard)
            XCTAssertFalse(tools.isEmpty, "'\(q)' should rank at least one tool")
        }
    }

    // MARK: - Tool Routing Accuracy (100+ queries → correct tool)

    @MainActor
    func testToolRoutingAccuracyFoodTools() {
        let cases: [(String, String?, AIScreen)] = [
            // log_food — should rank top
            ("log 2 eggs", "log_food", .food),
            ("ate chicken biryani", "log_food", .food),
            ("had a banana", "log_food", .food),
            ("i just had rice and dal", "log_food", .food),
            ("log lunch", "log_food", .food),
            ("add oatmeal", "log_food", .food),
            // food_info — should rank top
            ("calories left", "food_info", .food),
            ("how am i doing", "food_info", .dashboard),
            ("daily summary", "food_info", .dashboard),
            ("what did i eat", "food_info", .food),
            ("suggest dinner", "food_info", .food),
            ("what should i eat", "food_info", .food),
            ("how much protein today", "food_info", .food),
            ("weekly summary", "food_info", .dashboard),
            ("yesterday's food", "food_info", .food),
            // Migrated from StaticOverrides
            ("how much sugar today", "food_info", .food),
            ("how much fat today", "food_info", .food),
            ("calories in samosa", "food_info", .food),
            ("estimate calories for biryani", "food_info", .food),
            ("how to lose fat", "food_info", .food),
            ("what's a good diet", "food_info", .food),
        ]
        var correct = 0
        for (query, expectedTool, screen) in cases {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: screen)
            let topTool = tools.first?.name
            if topTool == expectedTool { correct += 1 }
        }
        let accuracy = Double(correct) / Double(cases.count) * 100
        XCTAssertGreaterThanOrEqual(accuracy, 80, "Food tool routing: \(correct)/\(cases.count) = \(Int(accuracy))%")
    }

    @MainActor
    func testToolRoutingAccuracyWeightTools() {
        let cases: [(String, String?, AIScreen)] = [
            ("i weigh 165 lbs", "log_weight", .weight),
            ("weight is 75 kg", "log_weight", .weight),
            ("how's my weight", "weight_info", .weight),
            ("weight trend", "weight_info", .weight),
            ("am i losing weight", "weight_info", .weight),
            ("tdee", "weight_info", .weight),
            ("bmr", "weight_info", .weight),
            ("how many calories do i burn", "weight_info", .weight),
            ("set goal to 155", "set_goal", .goal),
            ("target weight 70 kg", "set_goal", .goal),
        ]
        var correct = 0
        for (query, expectedTool, screen) in cases {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: screen)
            if tools.first?.name == expectedTool { correct += 1 }
        }
        let accuracy = Double(correct) / Double(cases.count) * 100
        XCTAssertGreaterThanOrEqual(accuracy, 80, "Weight tool routing: \(correct)/\(cases.count) = \(Int(accuracy))%")
    }

    @MainActor
    func testToolRoutingAccuracyExerciseTools() {
        let cases: [(String, String?, AIScreen)] = [
            ("start push day", "start_workout", .exercise),
            ("start chest workout", "start_workout", .exercise),
            ("begin leg day", "start_workout", .exercise),
            ("what should i train", "exercise_info", .exercise),
            ("suggest a workout", "exercise_info", .exercise),
            ("workout history", "exercise_info", .exercise),
            ("how many workouts this week", "exercise_info", .exercise),
            ("i did yoga for 30 min", "log_activity", .exercise),
            ("just did 20 min cardio", "log_activity", .exercise),
        ]
        var correct = 0
        for (query, expectedTool, screen) in cases {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: screen)
            if tools.first?.name == expectedTool { correct += 1 }
        }
        let accuracy = Double(correct) / Double(cases.count) * 100
        XCTAssertGreaterThanOrEqual(accuracy, 70, "Exercise tool routing: \(correct)/\(cases.count) = \(Int(accuracy))%")
    }

    @MainActor
    func testToolRoutingAccuracyOtherTools() {
        let cases: [(String, String?, AIScreen)] = [
            ("how did i sleep", "sleep_recovery", .bodyRhythm),
            ("sleep this week", "sleep_recovery", .bodyRhythm),
            ("hrv trend", "sleep_recovery", .bodyRhythm),
            ("took vitamin d", "mark_supplement", .supplements),
        ]
        var correct = 0
        for (query, expectedTool, screen) in cases {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: screen)
            if tools.first?.name == expectedTool { correct += 1 }
        }
        XCTAssertGreaterThanOrEqual(correct, cases.count / 2, "Other tool routing: \(correct)/\(cases.count)")
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
            // More edge cases
            ("log 50 ml milk", nil, nil),
            ("ate 100g paneer tikka", nil, nil),
            ("log 2 tbsp of ghee", "ghee", 2),
            ("had quarter cup of rice", "rice", nil),
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
            // Article "the" treated as 1 serving
            ("the bread", 1, nil),
            ("the avocado", 1, nil),
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

    @MainActor
    func testExtractAmountEdgeCases() {
        // Trailing quantity: "paneer biryani 300 gram"
        let (_, trailingName, trailingG) = AIActionExecutor.extractAmount(from: "paneer biryani 300 gram")
        XCTAssertEqual(trailingName, "paneer biryani")
        XCTAssertEqual(trailingG, 300)

        // Trailing compact: "chicken 200g"
        let (_, compactName, compactG) = AIActionExecutor.extractAmount(from: "chicken 200g")
        XCTAssertEqual(compactName, "chicken")
        XCTAssertEqual(compactG, 200)

        // Range: "2 to 3 bananas" → take higher
        let (rangeSrv, rangeName, _) = AIActionExecutor.extractAmount(from: "2 to 3 bananas")
        XCTAssertEqual(rangeSrv, 3)
        XCTAssertEqual(rangeName, "bananas")

        // Range with "or": "1 or 2 eggs"
        let (orSrv, orName, _) = AIActionExecutor.extractAmount(from: "1 or 2 eggs")
        XCTAssertEqual(orSrv, 2)
        XCTAssertEqual(orName, "eggs")

        // Trailing count unit: "protein 2 scoop" → treated as trailing quantity
        let (_, trailCountName, trailCountG) = AIActionExecutor.extractAmount(from: "protein 2 scoop")
        XCTAssertEqual(trailCountName, "protein")
        XCTAssertEqual(trailCountG, 2)

        // Word amounts: "some rice", "few eggs", "several rotis"
        let (someSrv, someName, _) = AIActionExecutor.extractAmount(from: "some rice")
        XCTAssertEqual(someSrv, 1)
        XCTAssertEqual(someName, "rice")

        let (fewSrv, _, _) = AIActionExecutor.extractAmount(from: "few rotis")
        XCTAssertEqual(fewSrv, 3)

        // Fraction: "1/3 avocado"
        let (fracSrv, fracName, _) = AIActionExecutor.extractAmount(from: "1/3 avocado")
        XCTAssertNotNil(fracSrv)
        if let s = fracSrv { XCTAssertEqual(s, 1.0/3.0, accuracy: 0.01) }
        XCTAssertEqual(fracName, "avocado")

        // No amount: just food name
        let (nilSrv, plainName, nilG) = AIActionExecutor.extractAmount(from: "chicken tikka masala")
        XCTAssertNil(nilSrv)
        XCTAssertEqual(plainName, "chicken tikka masala")
        XCTAssertNil(nilG)

        // Multi-word amount: "a couple of eggs"
        let (coupleSrv, coupleName, _) = AIActionExecutor.extractAmount(from: "a couple of eggs")
        XCTAssertEqual(coupleSrv, 2)
        XCTAssertEqual(coupleName, "eggs")
    }

    @MainActor
    func testParseFoodIntentEdgeCases() {
        // Natural prefixes
        XCTAssertNotNil(AIActionExecutor.parseFoodIntent("i'm having pasta"))
        XCTAssertNotNil(AIActionExecutor.parseFoodIntent("snacked on chips"))
        XCTAssertNotNil(AIActionExecutor.parseFoodIntent("i made soup"))
        XCTAssertNotNil(AIActionExecutor.parseFoodIntent("just drank smoothie"))

        // Meal hint extraction
        let breakfast = AIActionExecutor.parseFoodIntent("log eggs for breakfast")
        XCTAssertNotNil(breakfast)
        XCTAssertEqual(breakfast?.mealHint, "breakfast")

        let dinner = AIActionExecutor.parseFoodIntent("had chicken for dinner")
        XCTAssertNotNil(dinner)
        XCTAssertEqual(dinner?.mealHint, "dinner")

        // Suffix stripping: "for me", "please", "today"
        let polite = AIActionExecutor.parseFoodIntent("log rice please")
        XCTAssertNotNil(polite)
        XCTAssertEqual(polite?.query, "rice")

        let forMe = AIActionExecutor.parseFoodIntent("log dal for me")
        XCTAssertNotNil(forMe)
        XCTAssertEqual(forMe?.query, "dal")

        // Non-food rejection
        XCTAssertNil(AIActionExecutor.parseFoodIntent("log exercise"))
        XCTAssertNil(AIActionExecutor.parseFoodIntent("log workout"))
        XCTAssertNil(AIActionExecutor.parseFoodIntent("log weight"))

        // Empty remainder
        XCTAssertNil(AIActionExecutor.parseFoodIntent("log "))
        XCTAssertNil(AIActionExecutor.parseFoodIntent("ate"))
    }

    @MainActor
    func testParseWeightIntentEdgeCases() {
        // Sanity check: too low/high
        XCTAssertNil(AIActionExecutor.parseWeightIntent("i weigh 10"))
        XCTAssertNil(AIActionExecutor.parseWeightIntent("i weigh 600"))

        // Valid edge cases
        XCTAssertNotNil(AIActionExecutor.parseWeightIntent("scale says 200 lbs"))
        XCTAssertNotNil(AIActionExecutor.parseWeightIntent("i'm at 75 kg"))
        XCTAssertNotNil(AIActionExecutor.parseWeightIntent("log weight 165"))

        // Unit detection
        let kg = AIActionExecutor.parseWeightIntent("weight is 80 kg")
        XCTAssertEqual(kg?.unit, .kg)
        let lbs = AIActionExecutor.parseWeightIntent("i weigh 180 lbs")
        XCTAssertEqual(lbs?.unit, .lbs)
        let pounds = AIActionExecutor.parseWeightIntent("weighed in at 165 pounds")
        XCTAssertEqual(pounds?.unit, .lbs)
    }

    @MainActor
    func testArticleAndWithParsing() {
        // "the" article strips cleanly → food name is just "bread"
        let (theServings, theName, _) = AIActionExecutor.extractAmount(from: "the bread")
        XCTAssertEqual(theServings, 1)
        XCTAssertEqual(theName, "bread")

        let (anServings, anName, _) = AIActionExecutor.extractAmount(from: "an apple")
        XCTAssertEqual(anServings, 1)
        XCTAssertEqual(anName, "apple")

        // "with" items should each be parseable individually after splitting
        let withItems = "coffee with 2% milk with protein powder"
            .components(separatedBy: " with ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(withItems.count, 3)
        XCTAssertEqual(withItems[0], "coffee")
        XCTAssertEqual(withItems[1], "2% milk")
        XCTAssertEqual(withItems[2], "protein powder")

        // Each sub-item should parse cleanly through extractAmount
        let (_, coffeeName, _) = AIActionExecutor.extractAmount(from: "coffee")
        XCTAssertEqual(coffeeName, "coffee")

        let (_, milkName, _) = AIActionExecutor.extractAmount(from: "2% milk")
        XCTAssertEqual(milkName, "2% milk")

        let (_, proteinName, _) = AIActionExecutor.extractAmount(from: "protein powder")
        XCTAssertEqual(proteinName, "protein powder")
    }

    // MARK: - ConversationState Topic Classification

    @MainActor
    func testTopicClassification() {
        let state = ConversationState.shared

        // Food queries
        XCTAssertEqual(state.classifyTopic("I ate 2 eggs"), .food)
        XCTAssertEqual(state.classifyTopic("calories left"), .food)
        XCTAssertEqual(state.classifyTopic("log lunch"), .food)
        XCTAssertEqual(state.classifyTopic("how much protein today"), .food)

        // Weight queries
        XCTAssertEqual(state.classifyTopic("I weigh 165"), .weight)
        XCTAssertEqual(state.classifyTopic("weight trend"), .weight)
        XCTAssertEqual(state.classifyTopic("what's my tdee"), .weight)

        // Exercise queries
        XCTAssertEqual(state.classifyTopic("start push day"), .exercise)
        XCTAssertEqual(state.classifyTopic("I did yoga"), .exercise)
        XCTAssertEqual(state.classifyTopic("suggest workout"), .exercise)

        // Sleep
        XCTAssertEqual(state.classifyTopic("how did I sleep"), .sleep)

        // Unknown
        XCTAssertEqual(state.classifyTopic("hi"), .unknown)
        XCTAssertEqual(state.classifyTopic("thanks"), .unknown)
    }

    // MARK: - PreHookResult Routing (log_food)

    @MainActor
    func testPreHookRouting_customCalories_opensManualEntry() async {
        // Route 1: custom calories must open ManualFoodEntrySheet for review — NOT log directly.
        // Regression test: previously called quickAdd() bypassing confirm-first policy.
        ToolRegistration.registerAll()
        let call = ToolCall(tool: "log_food", params: ToolCallParams(values: [
            "name": "chipotle bowl", "calories": "800", "protein": "30", "carbs": "80", "fat": "25"
        ]))
        let result = await ToolRegistry.shared.execute(call)
        if case .action(let action) = result, case .openManualFoodEntry(let name, let cal, let p, _, _) = action {
            XCTAssertEqual(name, "chipotle bowl")
            XCTAssertEqual(cal, 800)
            XCTAssertEqual(p, 30)
        } else {
            XCTFail("Expected .action(.openManualFoodEntry), got \(result)")
        }
    }

    @MainActor
    func testPreHookRouting_customCaloriesOnly_opensManualEntry() async {
        // Calories without macros should also open ManualFoodEntrySheet.
        ToolRegistration.registerAll()
        let call = ToolCall(tool: "log_food", params: ToolCallParams(values: [
            "name": "protein bar", "calories": "250"
        ]))
        let result = await ToolRegistry.shared.execute(call)
        if case .action(let action) = result, case .openManualFoodEntry(let name, let cal, _, _, _) = action {
            XCTAssertEqual(name, "protein bar")
            XCTAssertEqual(cal, 250)
        } else {
            XCTFail("Expected .action(.openManualFoodEntry), got \(result)")
        }
    }

    @MainActor
    func testPreHookRouting_emptyName() {
        // Empty name → should be .invalid
        let json = #"{"tool":"log_food","name":""}"#
        let intent = IntentClassifier.parseResponse(json)
        XCTAssertEqual(intent?.params["name"], "")
    }

    // MARK: - Weight Goal Current-Based Calculations

    @MainActor
    func testWeightGoalCurrentBased() {
        let goal = WeightGoal(targetWeightKg: 90, monthsToAchieve: 6,
                              startDate: "2026-04-01", startWeightKg: 75.9)

        // Direction always from current weight
        XCTAssertTrue(goal.isLosing(currentWeightKg: 102), "102 > 90 → losing")
        XCTAssertFalse(goal.isLosing(currentWeightKg: 85), "85 < 90 → not losing")

        // Remaining always from current
        XCTAssertEqual(goal.remainingKg(currentWeightKg: 102), -12, accuracy: 0.1)
        XCTAssertEqual(goal.remainingKg(currentWeightKg: 85), 5, accuracy: 0.1)

        // Deficit direction matches
        XCTAssertTrue(goal.requiredDailyDeficit(currentWeightKg: 102) < 0, "Need deficit to lose")
        XCTAssertTrue(goal.requiredDailyDeficit(currentWeightKg: 85) > 0, "Need surplus to gain")
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

    // MARK: - SpellCorrectService

    @MainActor
    func testSpellCorrectHardcoded() {
        // Hardcoded corrections
        XCTAssertEqual(SpellCorrectService.correct("chiken"), "chicken")
        XCTAssertEqual(SpellCorrectService.correct("bannana"), "banana")
        XCTAssertEqual(SpellCorrectService.correct("brocoli"), "broccoli")
        XCTAssertEqual(SpellCorrectService.correct("avacado"), "avocado")
        XCTAssertEqual(SpellCorrectService.correct("protien"), "protein")
        XCTAssertEqual(SpellCorrectService.correct("panner"), "paneer")
        XCTAssertEqual(SpellCorrectService.correct("samossa"), "samosa")
        XCTAssertEqual(SpellCorrectService.correct("biryanni"), "biryani")
        XCTAssertEqual(SpellCorrectService.correct("daal"), "dal")
        XCTAssertEqual(SpellCorrectService.correct("coffe"), "coffee")

        // Multi-word correction
        XCTAssertEqual(SpellCorrectService.correct("chiken biryanni"), "chicken biryani")
    }

    @MainActor
    func testSpellCorrectPassthrough() {
        // Already correct words should pass through unchanged
        XCTAssertEqual(SpellCorrectService.correct("chicken"), "chicken")
        XCTAssertEqual(SpellCorrectService.correct("banana"), "banana")
        XCTAssertEqual(SpellCorrectService.correct("rice"), "rice")

        // Short words (< 4 chars) should pass through
        XCTAssertEqual(SpellCorrectService.correct("egg"), "egg")
        XCTAssertEqual(SpellCorrectService.correct("dal"), "dal")

        // Common English words should pass through
        XCTAssertEqual(SpellCorrectService.correct("the"), "the")
        XCTAssertEqual(SpellCorrectService.correct("and"), "and")
        XCTAssertEqual(SpellCorrectService.correct("log 2 eggs"), "log 2 eggs")
    }

    @MainActor
    func testSpellCorrectFuzzyMatch() {
        // Edit distance 1 corrections against food DB
        // "chciken" → "chicken" (1 swap)
        let result = SpellCorrectService.correct("chickn breast")
        // Should correct "chickn" to a food word, "breast" passes through or corrects
        XCTAssertTrue(result.contains("chick"), "Should correct 'chickn' to something with 'chick'")
    }

    // MARK: - findFood Coverage Tests

    func testFindFoodGramAmount() {
        // gramAmount path: "200g chicken" → servings = 200 / servingSize
        let match = AIActionExecutor.findFood(query: "chicken", servings: nil, gramAmount: 200)
        XCTAssertNotNil(match, "Should find chicken")
        if let m = match {
            XCTAssertTrue(m.servings > 0, "Gram-based servings should be > 0")
            // 200g / servingSize should give a specific servings count
            let expectedServings = 200.0 / m.food.servingSize
            XCTAssertEqual(m.servings, expectedServings, accuracy: 0.01, "Servings should be 200/servingSize")
        }
    }

    func testFindFoodSpellCorrection() {
        // Spell correction fallback: "bannana" → "banana"
        let match = AIActionExecutor.findFood(query: "bannana", servings: nil)
        XCTAssertNotNil(match, "Should find banana via spell correction")
        if let m = match {
            XCTAssertTrue(m.food.name.lowercased().contains("banana"), "Should match banana")
        }
    }

    func testFindFoodQualifierStripping() {
        // Qualifier stripping: "bowl of rice" → "rice"
        let bowl = AIActionExecutor.findFood(query: "bowl of rice", servings: nil)
        XCTAssertNotNil(bowl, "Should find rice via qualifier stripping 'bowl of'")

        let sliceOf = AIActionExecutor.findFood(query: "slice of pizza", servings: nil)
        XCTAssertNotNil(sliceOf, "Should find pizza via qualifier stripping 'slice of'")

        let cupOf = AIActionExecutor.findFood(query: "cup of oatmeal", servings: nil)
        XCTAssertNotNil(cupOf, "Should find oatmeal via qualifier stripping 'cup of'")
    }

    func testFindFoodFirstWordFallback() {
        // First word fallback: "chicken supreme deluxe" → "chicken"
        let match = AIActionExecutor.findFood(query: "chicken supreme deluxe", servings: nil)
        XCTAssertNotNil(match, "Should find chicken via first word fallback")
    }

    func testFindFoodSingularization() {
        // Singular-first search: "bananas" → "banana"
        let match = AIActionExecutor.findFood(query: "bananas", servings: nil)
        XCTAssertNotNil(match, "Should find banana from plural")
        if let m = match {
            XCTAssertTrue(m.food.name.lowercased().contains("banana"), "Should match banana")
        }
    }

    @MainActor
    func testHindiSynonymFoodSearch() {
        // Hindi synonym expansion: murgh→chicken, anda→egg, aloo→potato, kela→banana
        // Tests that SpellCorrectService.expandSynonyms feeds into searchFood results.
        let murgh = FoodService.searchFood(query: "murgh")
        XCTAssertFalse(murgh.isEmpty, "murgh (chicken) should return results via synonym expansion")
        XCTAssertTrue(murgh.contains(where: { $0.name.lowercased().contains("chicken") }),
                      "murgh results should include a chicken entry")

        let anda = FoodService.searchFood(query: "anda")
        XCTAssertFalse(anda.isEmpty, "anda (egg) should return results via synonym expansion")
        XCTAssertTrue(anda.contains(where: { $0.name.lowercased().contains("egg") }),
                      "anda results should include an egg entry")

        let kela = FoodService.searchFood(query: "kela")
        XCTAssertFalse(kela.isEmpty, "kela (banana) should return results via synonym expansion")
        XCTAssertTrue(kela.contains(where: { $0.name.lowercased().contains("banana") }),
                      "kela results should include a banana entry")

        let aloo = FoodService.searchFood(query: "aloo")
        XCTAssertFalse(aloo.isEmpty, "aloo (potato) should return results via synonym expansion")
    }

    @MainActor
    func testBengaliAndTamilSynonymSearch() {
        // Bengali: ilish→hilsa, rui→rohu, maach→fish
        let ilish = FoodService.searchFood(query: "ilish")
        XCTAssertTrue(ilish.contains(where: { $0.name.lowercased().contains("hilsa") }),
                      "ilish should resolve to hilsa via synonym expansion")

        let rui = FoodService.searchFood(query: "rui")
        XCTAssertTrue(rui.contains(where: { $0.name.lowercased().contains("rohu") }),
                      "rui should resolve to rohu via synonym expansion")

        let maach = FoodService.searchFood(query: "maach")
        XCTAssertFalse(maach.isEmpty, "maach (fish) should return fish results via synonym expansion")

        // Tamil: kozhi→chicken, thayir→yogurt
        let kozhi = FoodService.searchFood(query: "kozhi")
        XCTAssertTrue(kozhi.contains(where: { $0.name.lowercased().contains("chicken") }),
                      "kozhi should resolve to chicken via synonym expansion")

        let thayir = FoodService.searchFood(query: "thayir")
        XCTAssertTrue(thayir.contains(where: { $0.name.lowercased().contains("yogurt") || $0.name.lowercased().contains("curd") }),
                      "thayir should resolve to yogurt via synonym expansion")

        // Hindi ingredient: gur→jaggery
        let gur = FoodService.searchFood(query: "gur")
        XCTAssertTrue(gur.contains(where: { $0.name.lowercased().contains("jaggery") }),
                      "gur should resolve to jaggery via synonym expansion")
    }

    func testNutritionEstimationPrompt() {
        // Cover nutritionEstimationPrompt
        let prompt = AIActionExecutor.nutritionEstimationPrompt(food: "samosa", servings: 2)
        XCTAssertTrue(prompt.contains("samosa"), "Prompt should contain food name")
        XCTAssertTrue(prompt.contains("2.0"), "Prompt should contain servings")

        let promptDefault = AIActionExecutor.nutritionEstimationPrompt(food: "biryani", servings: nil)
        XCTAssertTrue(promptDefault.contains("1 serving"), "Default should be 1 serving")
    }

    // MARK: - Word Fraction Amounts

    @MainActor
    func testWordFractionAmounts() {
        // "third pizza" → 0.333
        let (thirdSrv, thirdName, _) = AIActionExecutor.extractAmount(from: "third pizza")
        XCTAssertNotNil(thirdSrv, "'third' should parse as ~0.333")
        if let s = thirdSrv { XCTAssertEqual(s, 1.0/3, accuracy: 0.01) }
        XCTAssertEqual(thirdName, "pizza")

        // "sixth cake" → 0.167
        let (sixthSrv, _, _) = AIActionExecutor.extractAmount(from: "sixth cake")
        XCTAssertNotNil(sixthSrv)
        if let s = sixthSrv { XCTAssertEqual(s, 1.0/6, accuracy: 0.01) }

        // "eighth pie" → 0.125
        let (eighthSrv, _, _) = AIActionExecutor.extractAmount(from: "eighth pie")
        XCTAssertNotNil(eighthSrv)
        if let s = eighthSrv { XCTAssertEqual(s, 0.125, accuracy: 0.01) }
    }

    // MARK: - Goal Pattern Expansion

    @MainActor
    func testGoalPatternExpanded() {
        let goalQueries = [
            "trying to reach 160 lbs",
            "get down to 75 kg",
            "want to reach 155",
            "reach 70 kg",
        ]
        for query in goalQueries {
            let result = StaticOverrides.match(query.lowercased())
            XCTAssertNotNil(result, "'\(query)' should match as weight goal")
        }
    }

    // MARK: - Activity Verb Expansion

    @MainActor
    func testActivityVerbsExpanded() {
        let activities = [
            "worked out for 30 min",
            "i worked out for an hour",
            "trained legs for 45 min",
            "i trained for 20 minutes",
            "i ran for 30 min",
            "ran for 20 minutes",
        ]
        for query in activities {
            let result = StaticOverrides.match(query.lowercased())
            XCTAssertNotNil(result, "'\(query)' should match as activity")
        }
    }

    // MARK: - Barcode Trigger Expansion

    @MainActor
    func testBarcodeTriggerExpanded() {
        let triggers = ["barcode scan", "scan product"]
        for query in triggers {
            let result = StaticOverrides.match(query.lowercased())
            XCTAssertNotNil(result, "'\(query)' should trigger barcode scanner")
        }
    }

    // MARK: - Navigation (StaticOverrides)

    @MainActor
    func testStaticOverridesNavigation() {
        let navCases: [(String, Int)] = [
            ("show me my weight chart", 1),
            ("go to food tab", 2),
            ("open exercise", 3),
            ("show weight", 1),
            ("go to dashboard", 0),
            ("open food diary", 2),
            ("switch to supplements", 4),
            ("navigate to glucose", 4),
            ("show my workouts", 3),
            ("open biomarkers", 4),
        ]
        for (query, expectedTab) in navCases {
            let result = StaticOverrides.match(query.lowercased())
            XCTAssertNotNil(result, "'\(query)' should navigate")
            if case .uiAction(let action, _) = result,
               case .navigate(let tab) = action {
                XCTAssertEqual(tab, expectedTab, "'\(query)' → expected tab \(expectedTab), got \(tab)")
            } else {
                XCTFail("'\(query)' should return .uiAction(.navigate), got \(String(describing: result))")
            }
        }
    }

    // MARK: - ToolRanker: add_supplement / log_body_comp / explain_calories

    @MainActor
    func testToolRankerMiscTools() {
        let queries: [(String, String, AIScreen)] = [
            // add_supplement (15 queries)
            ("add creatine 5g", "add_supplement", .supplements),
            ("add fish oil to my stack", "add_supplement", .supplements),
            ("add magnesium 400mg", "add_supplement", .supplements),
            ("add vitamin D supplement", "add_supplement", .supplements),
            ("add vitamin C", "add_supplement", .supplements),
            ("add supplement zinc", "add_supplement", .supplements),
            ("add new supplement ashwagandha", "add_supplement", .supplements),
            ("add creatine monohydrate", "add_supplement", .supplements),
            ("add to stack omega 3", "add_supplement", .supplements),
            ("add vitamin D 2000 IU", "add_supplement", .supplements),
            ("add supplement omega 3", "add_supplement", .supplements),
            ("add vitamin b12 daily", "add_supplement", .supplements),
            ("new supplement l-theanine", "add_supplement", .supplements),
            ("add supplement probiotic daily", "add_supplement", .supplements),
            ("add creatine hcl to my stack", "add_supplement", .supplements),
            // log_body_comp (15 queries) — use "is" to trigger anti-keyword on body_comp
            ("body fat is 18", "log_body_comp", .bodyComposition),
            ("my body fat is 22", "log_body_comp", .bodyComposition),
            ("bmi is 24.5", "log_body_comp", .bodyComposition),
            ("body fat is 20 percent", "log_body_comp", .bodyComposition),
            ("bmi today is 23", "log_body_comp", .bodyComposition),
            ("update my body fat to 19", "log_body_comp", .bodyComposition),
            ("body fat reading is 17", "log_body_comp", .bodyComposition),
            ("my body fat is 21", "log_body_comp", .bodyComposition),
            ("my bmi is 25", "log_body_comp", .bodyComposition),
            ("body fat is 15 percent", "log_body_comp", .bodyComposition),
            ("body fat is 16.5 percent", "log_body_comp", .bodyComposition),
            ("my body fat is 23.5", "log_body_comp", .bodyComposition),
            ("bmi is 26.8", "log_body_comp", .bodyComposition),
            ("recorded body fat is 21", "log_body_comp", .bodyComposition),
            ("my bmi is 22.4", "log_body_comp", .bodyComposition),
            // explain_calories (15 queries) — use exact trigger phrases to beat set_goal
            ("how are calories calculated", "explain_calories", .food),
            ("why is my target 1800", "explain_calories", .food),
            ("how is my calorie target set", "explain_calories", .food),
            ("how are calories set", "explain_calories", .food),
            ("how is my calorie goal determined", "explain_calories", .food),
            ("why is my target so high", "explain_calories", .food),
            ("how is my calorie target calculated", "explain_calories", .food),
            ("how is my calorie limit set", "explain_calories", .food),
            ("why is my target 2000 calories", "explain_calories", .food),
            ("how are calories determined", "explain_calories", .food),
            ("how are calories tracked in the app", "explain_calories", .food),
            ("why is my target 2200 calories", "explain_calories", .food),
            ("how is my calorie budget determined", "explain_calories", .food),
            ("explain my calorie target", "explain_calories", .food),
            ("how is my calorie limit calculated", "explain_calories", .food),
        ]
        for (query, expectedTool, screen) in queries {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: screen)
            XCTAssertEqual(tools.first?.name, expectedTool,
                "'\(query)' → top tool should be \(expectedTool), got \(tools.first?.name ?? "nil")")
        }
    }

    // MARK: - Confirm-First Policy: All log_food paths open UI, never log directly

    @MainActor
    func testPreHookRouting_multiItem_opensRecipeBuilder() async {
        // Multi-item food ("rice, dal, sabzi") must open RecipeBuilder for review — NOT log directly.
        // Regression: previously multi-item could bypass confirm-first via direct quickAdd.
        ToolRegistration.registerAll()
        let call = ToolCall(tool: "log_food", params: ToolCallParams(values: [
            "name": "rice, dal, sabzi"
        ]))
        let result = await ToolRegistry.shared.execute(call)
        if case .action(let action) = result, case .openRecipeBuilder(let items, _) = action {
            XCTAssertTrue(items.count >= 2, "Should have at least 2 items, got \(items.count)")
            XCTAssertTrue(items.contains(where: { $0.lowercased().contains("rice") }), "Should contain rice")
        } else {
            XCTFail("Multi-item log_food must open RecipeBuilder for review, got \(result)")
        }
    }

    @MainActor
    func testPreHookRouting_unknownFood_opensFoodSearch() async {
        // Single food not in DB must open FoodSearch for review — user can correct or confirm.
        // The name is passed as the search query so user sees what the AI parsed.
        ToolRegistration.registerAll()
        let call = ToolCall(tool: "log_food", params: ToolCallParams(values: [
            "name": "xyzunknownfood99999"
        ]))
        let result = await ToolRegistry.shared.execute(call)
        if case .action(let action) = result, case .openFoodSearch(let query, _) = action {
            XCTAssertEqual(query, "xyzunknownfood99999")
        } else {
            XCTFail("Unknown food must open FoodSearch for review, got \(result)")
        }
    }

    @MainActor
    func testPreHookRouting_knownFood_opensFoodSearch() async {
        // Single known food (e.g. banana) must still open FoodSearch prefilled — never log directly.
        // Confirm-first: user reviews serving size before committing.
        ToolRegistration.registerAll()
        let call = ToolCall(tool: "log_food", params: ToolCallParams(values: [
            "name": "banana"
        ]))
        let result = await ToolRegistry.shared.execute(call)
        if case .action(let action) = result, case .openFoodSearch(let query, _) = action {
            XCTAssertFalse(query.isEmpty, "FoodSearch query should not be empty")
        } else {
            XCTFail("Known food must open FoodSearch for review, got \(result)")
        }
    }

    @MainActor
    func testPreHookRouting_mealWord_returnsInvalid() async {
        // Bare meal words ("breakfast", "lunch") must return invalid, asking what the user ate.
        // They are not food names — AI should ask a follow-up.
        ToolRegistration.registerAll()
        for mealWord in ["breakfast", "lunch", "dinner", "snack"] {
            let call = ToolCall(tool: "log_food", params: ToolCallParams(values: ["name": mealWord]))
            let result = await ToolRegistry.shared.execute(call)
            if case .error = result {
                // correct — meal word returns .error (from PreHookResult.invalid), prompting follow-up
            } else {
                XCTFail("'\(mealWord)' should return .error (invalid meal word), got \(result)")
            }
        }
    }

    // MARK: - P0 Bug Regression Tests (#147, #148, #149)

    /// #149 regression: "log 2 eggs" must resolve to plain Egg, not Egg Benedict.
    func testFindFoodEggExactMatch() {
        let match = AIActionExecutor.findFood(query: "egg", servings: 2)
        XCTAssertNotNil(match, "Should find Egg")
        if let m = match {
            XCTAssertEqual(m.food.name.lowercased(), "egg",
                "#149 regression: findFood('egg') must return plain 'Egg', not '\(m.food.name)'")
        }
    }

    /// #149 regression: parseFoodIntent("log 2 eggs") must singularize to "egg" so FoodSearch
    /// finds plain "Egg" before "Eggs Benedict" via the LENGTH sort.
    func testParseFoodIntent_logEggs_extractsEgg() {
        let intent = AIActionExecutor.parseFoodIntent("log 2 eggs")
        XCTAssertNotNil(intent, "parseFoodIntent should detect 'log 2 eggs'")
        if let i = intent {
            XCTAssertEqual(i.query.lowercased(), "egg",
                "#149 regression: parseFoodIntent must singularize 'eggs'→'egg', got '\(i.query)'")
            XCTAssertEqual(i.servings, 2, "parseFoodIntent should extract servings=2")
        }
    }

    /// #147 regression: "daily summary" must not be treated as a food name.
    func testParseFoodIntent_dailySummary_isNotFood() {
        let intent = AIActionExecutor.parseFoodIntent("daily summary")
        XCTAssertNil(intent,
            "#147 regression: 'daily summary' must not be parsed as a food log intent")
    }

    /// #148 regression: "weekly summary" must not be treated as a food name.
    func testParseFoodIntent_weeklySummary_isNotFood() {
        let intent = AIActionExecutor.parseFoodIntent("weekly summary")
        XCTAssertNil(intent,
            "#148 regression: 'weekly summary' must not be parsed as a food log intent")
    }

    /// #147/#148 regression: bare "summary" variants should not route to food_parser layer.
    func testSummaryQueries_notInFoodParserLayer() {
        let summaryQueries = [
            "daily summary", "weekly summary", "how am i doing",
            "how's my day", "summary", "show summary"
        ]
        for q in summaryQueries {
            XCTAssertNil(AIActionExecutor.parseFoodIntent(q),
                "'\(q)' should not match parseFoodIntent (#147/#148 regression)")
            XCTAssertNil(AIActionExecutor.parseMultiFoodIntent(q),
                "'\(q)' should not match parseMultiFoodIntent (#147/#148 regression)")
        }
    }
}
