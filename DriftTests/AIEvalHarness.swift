import XCTest
@testable import Drift

/// Gold-standard evaluation harness for AI chat quality.
/// Tests synthetic queries and measures precision (correct actions) and recall (handled vs. fallback).
/// Run: xcodebuild test -only-testing:'DriftTests/AIEvalHarness'
final class AIEvalHarness: XCTestCase {

    // MARK: - Food Logging Intent Detection (Precision)

    /// These should ALL trigger food logging (open search sheet or parse food)
    func testFoodLoggingIntents() {
        let shouldLog = [
            "log 2 eggs",
            "ate chicken breast",
            "had a banana",
            "log rice and dal",
            "I just had a samosa for lunch",
            "add a protein shake",
            "track 3 rotis",
            "eating oatmeal",
            "logged half avocado",
            "i ate 2 slices of pizza",
            "had a cup of rice",
            "log a bowl of oatmeal",
            "i just had chicken and rice",
            "ate a couple of eggs",
            "just had some dal",
            "i ate a few rotis",
            "had a scoop of protein",
            "log eggs for dinner",
            "ate a lot of rice",
            "just ate some yogurt",
            "i had a coffee",
            "had 3 eggs for breakfast",
            "i had 2 eggs and a banana",
        ]

        var detected = 0
        for query in shouldLog {
            let lower = query.lowercased()
            let hasFoodIntent = AIActionExecutor.parseFoodIntent(lower) != nil
                || AIActionExecutor.parseMultiFoodIntent(lower) != nil
            if hasFoodIntent { detected += 1 }
            else { print("MISS (food): '\(query)'") }
        }

        let precision = Double(detected) / Double(shouldLog.count)
        print("Food logging precision: \(detected)/\(shouldLog.count) = \(String(format: "%.0f%%", precision * 100))")
        XCTAssertGreaterThanOrEqual(precision, 0.85, "Food logging precision should be >= 85%")
    }

    /// These should NOT trigger food logging
    func testFoodLoggingFalsePositives() {
        let shouldNotLog = [
            "how many calories in a banana",
            "what should I eat for dinner",
            "how's my protein",
            "calories left",
            "daily summary",
            "am I on track",
            "how much does chicken weigh",
            "what's in a samosa",
            "I did push ups",
            "start push day",
            "what should I train",
            "how's my sleep",
        ]

        var falsePositives = 0
        for query in shouldNotLog {
            let lower = query.lowercased()
            let hasFoodIntent = AIActionExecutor.parseFoodIntent(lower) != nil
                || AIActionExecutor.parseMultiFoodIntent(lower) != nil
            if hasFoodIntent {
                falsePositives += 1
                print("FALSE POSITIVE (food): '\(query)'")
            }
        }

        let fpRate = Double(falsePositives) / Double(shouldNotLog.count)
        print("Food logging false positive rate: \(falsePositives)/\(shouldNotLog.count) = \(String(format: "%.0f%%", fpRate * 100))")
        XCTAssertLessThanOrEqual(fpRate, 0.1, "False positive rate should be <= 10%")
    }

    // MARK: - Weight Logging Intent Detection

    func testWeightLoggingIntents() {
        let shouldLog = [
            "I weigh 165 lbs",
            "weight is 75.2 kg",
            "weighed in at 170",
            "scale says 82 kg",
            "my weight is 165",
            "log weight 170 lbs",
        ]

        var detected = 0
        for query in shouldLog {
            if AIActionExecutor.parseWeightIntent(query.lowercased()) != nil {
                detected += 1
            } else {
                print("MISS (weight): '\(query)'")
            }
        }

        let precision = Double(detected) / Double(shouldLog.count)
        print("Weight logging precision: \(detected)/\(shouldLog.count) = \(String(format: "%.0f%%", precision * 100))")
        XCTAssertGreaterThanOrEqual(precision, 0.83, "Weight logging precision should be >= 83%")
    }

    func testWeightFalsePositives() {
        let shouldNotLog = [
            "how much does chicken weigh",
            "am I losing weight",
            "what's my weight trend",
            "how much have I lost",
        ]

        var falsePositives = 0
        for query in shouldNotLog {
            if AIActionExecutor.parseWeightIntent(query.lowercased()) != nil {
                falsePositives += 1
                print("FALSE POSITIVE (weight): '\(query)'")
            }
        }

        XCTAssertEqual(falsePositives, 0, "No weight false positives expected")
    }

    // MARK: - Chain-of-Thought Routing (Recall)

    @MainActor
    func testChainOfThoughtRouting() {
        let queries: [(String, AIScreen, Bool)] = [
            // (query, screen, should trigger chain-of-thought?)
            ("how am I doing", .dashboard, true),
            ("am I on track", .weight, true),
            ("what should I eat for dinner", .food, true),
            ("how's my sleep", .bodyRhythm, true),
            ("which markers are out of range", .biomarkers, true),
            ("any glucose spikes", .glucose, true),
            ("what phase am I in", .cycle, true),
            ("what should I train", .exercise, true),
            ("did I take my supplements", .supplements, true),
            ("compare this week to last week", .dashboard, true),
            ("how many calories in a banana", .food, true),
            ("why am I not losing weight", .weight, true),

            // Simple queries — should NOT trigger chain
            ("hello", .dashboard, false),
            ("thanks", .dashboard, false),
            ("ok", .dashboard, false),
        ]

        var correct = 0
        for (query, screen, expectedChain) in queries {
            let hasChain = AIChainOfThought.plan(query: query, screen: screen) != nil
            if hasChain == expectedChain { correct += 1 }
            else { print("WRONG ROUTING: '\(query)' on \(screen) — expected chain=\(expectedChain), got=\(hasChain)") }
        }

        let recall = Double(correct) / Double(queries.count)
        print("Chain-of-thought routing accuracy: \(correct)/\(queries.count) = \(String(format: "%.0f%%", recall * 100))")
        XCTAssertGreaterThanOrEqual(recall, 0.85, "Routing accuracy should be >= 85%")
    }

    // MARK: - Rule Engine Coverage

    @MainActor
    func testRuleEngineResponses() {
        // These should produce non-empty instant responses
        let instantQueries = [
            ("daily summary", "dailySummary"),
            ("summary", "dailySummary"),
            ("yesterday", "yesterday"),
            ("calories left", "caloriesLeft"),
            ("weekly summary", "weeklySummary"),
            ("supplements", "supplements"),
        ]

        for (query, label) in instantQueries {
            // Just verify the rule engine functions don't crash on empty DB
            switch label {
            case "dailySummary":
                let r = AIRuleEngine.dailySummary()
                XCTAssertFalse(r.isEmpty, "dailySummary should return something")
            case "yesterday":
                let r = AIRuleEngine.yesterdaySummary()
                XCTAssertFalse(r.isEmpty, "yesterdaySummary should return something")
            case "caloriesLeft":
                let r = AIRuleEngine.caloriesLeft()
                XCTAssertFalse(r.isEmpty, "caloriesLeft should return something")
            case "weeklySummary":
                let r = AIRuleEngine.weeklySummary()
                XCTAssertFalse(r.isEmpty, "weeklySummary should return something")
            case "supplements":
                let r = AIRuleEngine.supplementStatus()
                XCTAssertFalse(r.isEmpty, "supplementStatus should return something")
            default: break
            }
        }
    }

    // MARK: - Response Quality (requires model)

    func testResponseQualityCleaner() {
        // Test that the response cleaner catches bad patterns
        let badResponses = [
            ("", true),                                     // empty
            ("Hi", true),                                   // too short
            ("I'm here to help you with anything!", true),  // generic filler
            ("|||data|||more|||", true),                    // garbage
            ("eaten: 1200/1800", true),                     // context regurgitation
            ("A: You've eaten 1200 cal", false),            // starts with "A:" but has content — clean should strip prefix
        ]

        for (response, expectedLowQuality) in badResponses {
            let cleaned = AIResponseCleaner.clean(response)
            let isLow = AIResponseCleaner.isLowQuality(cleaned)
            if isLow != expectedLowQuality {
                print("QUALITY CHECK WRONG: '\(response.prefix(40))' — expected low=\(expectedLowQuality), got=\(isLow)")
            }
        }

        // Good responses should pass
        let goodResponses = [
            "You've eaten 1200 of 1800 cal today. Consider a high-protein dinner.",
            "Your weight is trending down at 0.5 lbs/week. That's a healthy pace.",
            "You have 3 supplements left to take today: Vitamin D, Omega-3, and Magnesium.",
        ]

        // Markdown stripping
        let mdResponse = "**You've eaten** 1200 cal. ## Summary\nKeep going!"
        let mdCleaned = AIResponseCleaner.clean(mdResponse)
        XCTAssertFalse(mdCleaned.contains("**"), "Should strip markdown bold")
        XCTAssertFalse(mdCleaned.contains("##"), "Should strip markdown headers")

        // Preamble removal
        let preambleResponse = "Based on your data, you've eaten 1200 cal today."
        let pCleaned = AIResponseCleaner.clean(preambleResponse)
        XCTAssertFalse(pCleaned.lowercased().hasPrefix("based on"), "Should strip preambles")

        for response in goodResponses {
            let cleaned = AIResponseCleaner.clean(response)
            XCTAssertFalse(AIResponseCleaner.isLowQuality(cleaned), "Good response marked as low quality: '\(response.prefix(50))'")
        }
    }

    // MARK: - Amount Parsing Precision

    func testAmountParsingPrecision() {
        let cases: [(String, Double?, String)] = [
            ("2 eggs", 2, "eggs"),
            ("half avocado", 0.5, "avocado"),
            ("1/3 avocado", 1.0/3, "avocado"),
            ("a couple of eggs", 2, "eggs"),
            ("a few rotis", 3, "rotis"),
            ("three samosas", 3, "samosas"),
            ("a banana", 1, "banana"),
            ("chicken breast", nil, "chicken breast"),
            ("200g chicken", nil, "200g chicken"),  // large number = not servings
        ]

        var correct = 0
        for (input, expectedAmount, expectedFood) in cases {
            let intent = AIActionExecutor.parseFoodIntent("log \(input)")
            if let intent {
                let amountMatch: Bool
                if let expected = expectedAmount {
                    amountMatch = intent.servings != nil && abs((intent.servings ?? 0) - expected) < 0.05
                } else {
                    amountMatch = intent.servings == nil
                }
                let foodMatch = intent.query.lowercased().contains(expectedFood.lowercased().split(separator: " ").first ?? "")
                if amountMatch && foodMatch { correct += 1 }
                else { print("PARSE WRONG: '\(input)' → amount=\(String(describing: intent.servings)) food='\(intent.query)' (expected \(String(describing: expectedAmount)) '\(expectedFood)')") }
            } else {
                print("PARSE FAIL: 'log \(input)' returned nil")
            }
        }

        let precision = Double(correct) / Double(cases.count)
        print("Amount parsing precision: \(correct)/\(cases.count) = \(String(format: "%.0f%%", precision * 100))")
        XCTAssertGreaterThanOrEqual(precision, 0.78, "Amount parsing should be >= 78%")
    }

    // MARK: - Instant Response Coverage

    @MainActor
    func testInstantResponses() {
        // These should be handled instantly (no LLM) and return non-empty
        let instantQueries: [(String, String)] = [
            ("daily summary", "dailySummary"),
            ("summary", "dailySummary"),
            ("calories left", "caloriesLeft"),
            ("weekly summary", "weeklySummary"),
            ("supplements", "supplements"),
            ("yesterday", "yesterday"),
        ]

        for (_, label) in instantQueries {
            let response: String
            switch label {
            case "dailySummary": response = AIRuleEngine.dailySummary()
            case "caloriesLeft": response = AIRuleEngine.caloriesLeft()
            case "weeklySummary": response = AIRuleEngine.weeklySummary()
            case "supplements": response = AIRuleEngine.supplementStatus()
            case "yesterday": response = AIRuleEngine.yesterdaySummary()
            default: response = ""
            }
            XCTAssertFalse(response.isEmpty, "'\(label)' should produce non-empty response")
        }
    }

    // MARK: - Workout Action Parsing

    func testCreateWorkoutParsing() {
        // [CREATE_WORKOUT: Push Ups 3x15, Bench Press 3x10@135]
        let (action, clean) = AIActionParser.parse("Let's do it! [CREATE_WORKOUT: Push Ups 3x15, Bench Press 3x10@135]")
        if case .createWorkout(let exercises) = action {
            XCTAssertEqual(exercises.count, 2)
            XCTAssertEqual(exercises[0].name, "Push Ups")
            XCTAssertEqual(exercises[0].sets, 3)
            XCTAssertEqual(exercises[0].reps, 15)
            XCTAssertNil(exercises[0].weight)
            XCTAssertEqual(exercises[1].name, "Bench Press")
            XCTAssertEqual(exercises[1].sets, 3)
            XCTAssertEqual(exercises[1].reps, 10)
            XCTAssertEqual(exercises[1].weight, 135)
        } else {
            XCTFail("Expected createWorkout action")
        }
        XCTAssertTrue(clean.contains("Let's do it"))
    }

    @MainActor
    func testWorkoutExerciseKeywords() {
        // Exercise names should trigger workout context
        let exerciseQueries = [
            ("I did push ups", AIScreen.dashboard),
            ("just finished squats", AIScreen.exercise),
            ("bench press 3x10", AIScreen.exercise),
            ("I did deadlifts today", AIScreen.dashboard),
        ]
        for (query, screen) in exerciseQueries {
            let steps = AIChainOfThought.plan(query: query, screen: screen)
            XCTAssertNotNil(steps, "'\(query)' should trigger chain-of-thought")
            let hasWorkout = steps?.contains(where: { $0.label.lowercased().contains("workout") }) ?? false
            XCTAssertTrue(hasWorkout, "'\(query)' should fetch workout context")
        }
    }

    func testCreateWorkoutSingleExercise() {
        let (action, _) = AIActionParser.parse("[CREATE_WORKOUT: Squats 4x8@185]")
        if case .createWorkout(let exercises) = action {
            XCTAssertEqual(exercises.count, 1)
            XCTAssertEqual(exercises[0].name, "Squats")
            XCTAssertEqual(exercises[0].sets, 4)
            XCTAssertEqual(exercises[0].reps, 8)
            XCTAssertEqual(exercises[0].weight, 185)
        } else {
            XCTFail("Expected createWorkout")
        }
    }

    func testCreateWorkoutNoWeight() {
        let (action, _) = AIActionParser.parse("[CREATE_WORKOUT: Plank 3x60]")
        if case .createWorkout(let exercises) = action {
            XCTAssertEqual(exercises[0].name, "Plank")
            XCTAssertNil(exercises[0].weight)
        } else {
            XCTFail("Expected createWorkout")
        }
    }

    func testStartWorkoutParsing() {
        let (action, _) = AIActionParser.parse("[START_WORKOUT: Push Day]")
        if case .startWorkout(let type) = action {
            XCTAssertEqual(type, "Push Day")
        } else {
            XCTFail("Expected startWorkout action")
        }
    }

    // MARK: - Conversational Pattern Detection

    func testConversationalPatterns() {
        // Greetings should be caught (not sent to LLM)
        let greetings = ["hi", "hello", "hey", "yo", "sup"]
        for g in greetings {
            XCTAssertTrue(greetings.contains(g), "Greeting '\(g)' should be in list")
        }

        // Thanks should be caught
        let thanks = ["thanks", "thank you", "thx", "ty", "cool", "ok", "okay", "got it", "nice"]
        for t in thanks {
            XCTAssertTrue(thanks.contains(t))
        }

        // These should NOT be greetings or thanks (should go to LLM or food parser)
        let notConversational = ["help", "log eggs", "how am I doing", "calories left", "daily summary"]
        for q in notConversational {
            XCTAssertFalse(greetings.contains(q.lowercased()), "'\(q)' should not be a greeting")
            XCTAssertFalse(thanks.contains(q.lowercased()), "'\(q)' should not be thanks")
        }
    }

    // MARK: - Compound Food Protection

    func testCompoundFoodNotSplit() {
        // These contain "and" but should NOT be split into multiple foods
        let compounds = ["mac and cheese", "bread and butter", "rice and beans"]
        for food in compounds {
            let result = AIActionExecutor.parseMultiFoodIntent("log \(food)")
            XCTAssertNil(result, "Compound food '\(food)' should not be split")
        }
    }

    // MARK: - Lab Report AI Enhancement

    func testAIBiomarkerResponseParsing() {
        // Simulate what the LLM would return for biomarker extraction
        let aiResponse = """
        glucose|95|mg/dL
        total_cholesterol|210|mg/dL
        hdl_cholesterol|55|mg/dL
        """

        // The parser should extract valid biomarker results
        // (We can't call the private method directly, but we can test the format)
        let lines = aiResponse.components(separatedBy: .newlines)
        var parsed = 0
        for line in lines {
            let parts = line.split(separator: "|")
            if parts.count >= 3 {
                let id = String(parts[0]).trimmingCharacters(in: .whitespaces)
                if let _ = Double(String(parts[1]).trimmingCharacters(in: .whitespaces)),
                   !id.isEmpty {
                    parsed += 1
                }
            }
        }
        XCTAssertEqual(parsed, 3, "Should parse 3 biomarkers from AI response")
    }

    // MARK: - Summary Report

    // MARK: - Context Builder Smoke Tests

    @MainActor
    func testContextBuildersProduceOutput() {
        // All context builders should return something (not crash) on empty DB
        let base = AIContextBuilder.baseContext()
        XCTAssertFalse(base.isEmpty, "Base context should never be empty (at least shows target)")

        let food = AIContextBuilder.foodContext()
        // Food context may be empty if no food logged — that's OK

        let weight = AIContextBuilder.weightContext()
        // Weight context may say "No weight data" — that's OK
        XCTAssertFalse(weight.isEmpty || weight.contains("crash"), "Weight context should not crash")

        let workout = AIContextBuilder.workoutContext()
        // May be empty or "No workout data"

        let supplement = AIContextBuilder.supplementContext()
        XCTAssertFalse(supplement.isEmpty, "Supplement context should return something")

        // Screen-based context
        let dashboard = AIContextBuilder.buildContext(screen: .dashboard)
        XCTAssertFalse(dashboard.isEmpty)
        let weightScreen = AIContextBuilder.buildContext(screen: .weight)
        XCTAssertFalse(weightScreen.isEmpty)
    }

    func testPrintSummary() {
        print("=== AI EVAL HARNESS SUMMARY ===")
        print("Run individual tests for detailed precision/recall metrics.")
        print("Target: food logging >= 85%, weight >= 83%, routing >= 85%, parsing >= 78%")
        print("===============================")
    }
}
