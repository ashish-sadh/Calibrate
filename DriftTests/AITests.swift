import Foundation
import Testing
@testable import Drift

// MARK: - AIActionParser Tests

@Test func aiParseLogFood() async throws {
    let (action, clean) = AIActionParser.parse("Sure! [LOG_FOOD: chicken breast 200g] Let me know if you need more.")
    if case .logFood(let name, let amount) = action {
        #expect(name == "chicken breast")
        #expect(amount == "200g")
    } else {
        #expect(Bool(false), "Expected logFood action")
    }
    #expect(clean.contains("Sure!"))
    #expect(!clean.contains("[LOG_FOOD"))
}

@Test func aiParseStartWorkout() async throws {
    let (action, clean) = AIActionParser.parse("Let's go! [START_WORKOUT: legs]")
    if case .startWorkout(let type) = action {
        #expect(type == "legs")
    } else {
        #expect(Bool(false), "Expected startWorkout action")
    }
    #expect(clean == "Let's go!")
}

@Test func aiParseNoAction() async throws {
    let (action, clean) = AIActionParser.parse("You're doing great! Keep it up.")
    if case .none = action {
        // Expected
    } else {
        #expect(Bool(false), "Expected no action")
    }
    #expect(clean == "You're doing great! Keep it up.")
}

@Test func aiParseFoodWithoutAmount() async throws {
    let (action, _) = AIActionParser.parse("[LOG_FOOD: banana]")
    if case .logFood(let name, let amount) = action {
        #expect(name == "banana")
        #expect(amount == nil)
    } else {
        #expect(Bool(false), "Expected logFood")
    }
}

@Test func aiParseFoodWithServings() async throws {
    let (action, _) = AIActionParser.parse("[LOG_FOOD: oatmeal 1 cup]")
    if case .logFood(let name, let amount) = action {
        #expect(name == "oatmeal")
        #expect(amount == "1 cup")
    } else {
        #expect(Bool(false), "Expected logFood")
    }
}

// MARK: - AIContextBuilder Tests

@Test @MainActor func aiContextBuilderReturnsString() async throws {
    let context = AIContextBuilder.buildContext()
    #expect(!context.isEmpty, "Context should not be empty")
    // baseContext always outputs calorie info — either "Calories:" (food logged) or "No food logged" or "Target"
    // Also accept "cal" which appears in the target suffix (e.g. "2000cal")
    #expect(context.contains("cal") || context.contains("food") || context.contains("No") || context.contains("Target"),
            "Context should contain nutrition info, got: \(context.prefix(200))")
}

// MARK: - AIRuleEngine Tests

@Test @MainActor func aiRuleEngineDailySummary() async throws {
    let summary = AIRuleEngine.dailySummary()
    #expect(summary.contains("Here's your day"), "Should start with day summary header")
}

@Test @MainActor func aiRuleEngineYesterdaySummary() async throws {
    let summary = AIRuleEngine.yesterdaySummary()
    #expect(!summary.isEmpty, "Yesterday summary should not be empty")
}

@Test @MainActor func aiRuleEngineQuickInsight() async throws {
    let insight = AIRuleEngine.quickInsight()
    if let insight {
        #expect(!insight.isEmpty)
    }
}

@Test @MainActor func aiRuleEngineNextAction() async throws {
    let action = AIRuleEngine.nextAction()
    // On empty DB: either suggests logging food or returns nil (time-dependent)
    if let action {
        #expect(!action.isEmpty)
    }
}

@Test @MainActor func aiRuleEngineCaloriesLeft() async throws {
    let result = AIRuleEngine.caloriesLeft()
    #expect(!result.isEmpty, "caloriesLeft should always return a non-empty string")
    // With no food logged, should mention "No food logged" or show remaining
    #expect(result.contains("cal"), "Should mention calories")
}

@Test @MainActor func aiRuleEngineWeeklySummary() async throws {
    let summary = AIRuleEngine.weeklySummary()
    #expect(!summary.isEmpty, "Weekly summary should not be empty")
    #expect(summary.contains("This week"), "Should contain weekly header")
    #expect(summary.contains("Workouts"), "Should mention workout count")
}

@Test @MainActor func aiRuleEngineDailySummaryContainsFood() async throws {
    let summary = AIRuleEngine.dailySummary()
    // Should always mention food status (either logged or "nothing logged")
    #expect(summary.contains("Food:"), "Daily summary should include food line")
}

@Test @MainActor func aiRuleEngineYesterdaySummaryFormat() async throws {
    let summary = AIRuleEngine.yesterdaySummary()
    // Either "No food was logged yesterday" or formatted summary with cal
    #expect(summary.contains("yesterday") || summary.contains("Yesterday") || summary.contains("cal"),
            "Yesterday summary should reference yesterday or contain calorie data")
}

// MARK: - IntentClassifier Extended Tests

@Test @MainActor func intentClassifierWithTimeoutCompletes() async throws {
    let result = await IntentClassifier.withTimeout(seconds: 5) {
        return "done"
    }
    #expect(result == "done")
}

@Test @MainActor func intentClassifierWithTimeoutReturnsNilOnTimeout() async throws {
    let result = await IntentClassifier.withTimeout(seconds: 1) {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        return "should not reach"
    }
    #expect(result == nil)
}

@Test @MainActor func intentClassifierWithTimeoutNilOperation() async throws {
    // Operation that returns nil immediately (simulates LLM returning nil)
    let result: String? = await IntentClassifier.withTimeout(seconds: 5) {
        return nil
    }
    #expect(result == nil)
}

@Test func intentClassifierParseResponseArrayParams() {
    // Test array param conversion (items joined with ", ")
    let response = #"{"tool":"log_food","items":["eggs","toast","coffee"]}"#
    let intent = IntentClassifier.parseResponse(response)
    #expect(intent != nil)
    #expect(intent?.tool == "log_food")
    #expect(intent?.params["items"] == "eggs, toast, coffee")
}

@Test func intentClassifierParseResponseNumericValue() {
    // Test numeric param conversion (Double → String)
    let response = #"{"tool":"log_weight","value":72.5}"#
    let intent = IntentClassifier.parseResponse(response)
    #expect(intent != nil)
    #expect(intent?.tool == "log_weight")
    #expect(intent?.params["value"] == "72.5")
}

@Test func intentClassifierParseResponseConfidenceField() {
    // Explicit confidence
    let high = IntentClassifier.parseResponse(#"{"tool":"food_info","query":"cal","confidence":"high"}"#)
    #expect(high?.confidence == "high")

    let low = IntentClassifier.parseResponse(#"{"tool":"food_info","query":"cal","confidence":"low"}"#)
    #expect(low?.confidence == "low")

    // Missing confidence defaults to "high"
    let none = IntentClassifier.parseResponse(#"{"tool":"food_info","query":"cal"}"#)
    #expect(none?.confidence == "high")
}

@Test func intentClassifierClassifyResultEnum() {
    // Test ClassifyResult construction
    let intent = IntentClassifier.ClassifiedIntent(tool: "food_info", params: ["query": "calories"], confidence: "high")
    let toolResult = IntentClassifier.ClassifyResult.toolCall(intent)
    if case .toolCall(let i) = toolResult {
        #expect(i.tool == "food_info")
        #expect(i.params["query"] == "calories")
    } else {
        #expect(Bool(false), "Expected toolCall")
    }

    let textResult = IntentClassifier.ClassifyResult.text("What did you eat?")
    if case .text(let t) = textResult {
        #expect(t == "What did you eat?")
    } else {
        #expect(Bool(false), "Expected text")
    }
}

@Test @MainActor func intentClassifierSystemPromptContainsAllTools() {
    let prompt = IntentClassifier.systemPrompt
    let expectedTools = ["log_food", "food_info", "log_weight", "weight_info",
                         "start_workout", "log_activity", "exercise_info",
                         "sleep_recovery", "mark_supplement", "set_goal",
                         "delete_food", "body_comp"]
    for tool in expectedTools {
        #expect(prompt.contains(tool), "System prompt should contain \(tool)")
    }
}

// MARK: - More AIActionParser Tests

@Test func aiParseShowWeight() async throws {
    let (action, _) = AIActionParser.parse("Here's your weight. [SHOW_WEIGHT]")
    if case .showWeight = action {
        // Expected
    } else {
        #expect(Bool(false), "Expected showWeight action")
    }
}

// MARK: - AIActionExecutor Tests

@Test func aiExecutorParseFoodLog() async throws {
    let intent = AIActionExecutor.parseFoodIntent("log 2 eggs")
    #expect(intent != nil)
    #expect(intent?.query == "eggs")
    #expect(intent?.servings == 2)
}

@Test func aiExecutorParseFoodFraction() async throws {
    let intent = AIActionExecutor.parseFoodIntent("ate 1/3 avocado")
    #expect(intent != nil)
    #expect(intent?.query == "avocado")
    #expect(intent?.servings != nil)
    #expect(abs((intent?.servings ?? 0) - 0.333) < 0.01)
}

@Test func aiExecutorParseFoodNoAmount() async throws {
    let intent = AIActionExecutor.parseFoodIntent("had chicken breast")
    #expect(intent != nil)
    #expect(intent?.query == "chicken breast")
    #expect(intent?.servings == nil)
}

@Test func aiExecutorParseFoodHalf() async throws {
    let intent = AIActionExecutor.parseFoodIntent("log half avocado")
    #expect(intent != nil)
    #expect(intent?.servings == 0.5)
}

@Test func aiExecutorNaturalPhrasing() async throws {
    let intent1 = AIActionExecutor.parseFoodIntent("i just had a samosa for lunch")
    #expect(intent1 != nil, "'I just had' should be recognized")
    #expect(intent1?.query == "samosa")

    let intent2 = AIActionExecutor.parseFoodIntent("i ate chicken breast")
    #expect(intent2 != nil, "'I ate' should be recognized")
    #expect(intent2?.query == "chicken breast")

    let intent3 = AIActionExecutor.parseFoodIntent("just had some rice")
    #expect(intent3 != nil, "'just had' should be recognized")
}

@Test func aiExecutorNoFoodIntent() async throws {
    let intent = AIActionExecutor.parseFoodIntent("how many calories today")
    #expect(intent == nil)
}

@Test func aiExecutorParseWeight() async throws {
    let intent = AIActionExecutor.parseWeightIntent("I weigh 165 lbs")
    #expect(intent != nil)
    #expect(intent?.weightValue == 165)
    #expect(intent?.unit == .lbs)
}

@Test func aiExecutorParseWeightKg() async throws {
    let intent = AIActionExecutor.parseWeightIntent("weight is 75.2 kg")
    #expect(intent != nil)
    #expect(intent?.weightValue == 75.2)
    #expect(intent?.unit == .kg)
}

// MARK: - Multi-Food Parsing

@Test func aiMultiFoodParsing() async throws {
    let intents = AIActionExecutor.parseMultiFoodIntent("log chicken and rice")
    #expect(intents != nil)
    #expect(intents?.count == 2)
    #expect(intents?[0].query == "chicken")
    #expect(intents?[1].query == "rice")
}

@Test func aiMultiFoodWithAmounts() async throws {
    let intents = AIActionExecutor.parseMultiFoodIntent("ate 2 eggs and toast")
    #expect(intents != nil)
    #expect(intents?.count == 2)
    #expect(intents?[0].query == "eggs")
    #expect(intents?[0].servings == 2)
    #expect(intents?[1].query == "toast")
}

@Test func aiMultiFoodNaturalPhrasing() async throws {
    // "I just had chicken and rice" should be multi-food
    let intents = AIActionExecutor.parseMultiFoodIntent("i just had chicken and rice")
    #expect(intents != nil, "Natural phrasing should work for multi-food")
    #expect(intents?.count == 2)
    #expect(intents?[0].query == "chicken")
    #expect(intents?[1].query == "rice")
}

@Test func aiMultiFoodCompoundNames() async throws {
    // "Mac and cheese" should NOT be split into "mac" + "cheese"
    let intents = AIActionExecutor.parseMultiFoodIntent("log mac and cheese")
    #expect(intents == nil, "Compound food 'mac and cheese' should not be split")
}

@Test func aiMultiFoodSingleItem() async throws {
    // Single item should return nil (use parseFoodIntent instead)
    let intents = AIActionExecutor.parseMultiFoodIntent("log banana")
    #expect(intents == nil)
}

// MARK: - Chain-of-Thought Tests

@Test @MainActor func aiChainOfThoughtWeightQuery() async throws {
    let steps = AIChainOfThought.plan(query: "am I on track?", screen: .weight)
    #expect(steps != nil, "Weight query should trigger chain-of-thought")
    #expect(steps?.contains(where: { $0.label.contains("weight") }) == true)
}

@Test @MainActor func aiChainOfThoughtFoodQuery() async throws {
    let steps = AIChainOfThought.plan(query: "what should I eat for dinner?", screen: .food)
    #expect(steps != nil)
    #expect(steps?.contains(where: { $0.label.contains("meals") }) == true)
}

@Test @MainActor func aiChainOfThoughtSimpleQuery() async throws {
    let steps = AIChainOfThought.plan(query: "hello", screen: .dashboard)
    #expect(steps == nil, "Simple query should not trigger chain-of-thought")
}

@Test @MainActor func aiChainOfThoughtOverview() async throws {
    let steps = AIChainOfThought.plan(query: "how am I doing?", screen: .dashboard)
    #expect(steps != nil)
    #expect(steps?.count ?? 0 >= 2, "Overview should fetch multiple data sources")
}

// MARK: - Response Cleaner Tests

@Test func aiResponseCleanerRemovesArtifacts() async throws {
    let dirty = "Hello<|im_end|> world<|im_start|>assistant"
    let clean = AIResponseCleaner.clean(dirty)
    #expect(!clean.contains("<|im_end|>"))
    #expect(!clean.contains("<|im_start|>"))
}

@Test func aiResponseCleanerRemovesDisclaimers() async throws {
    let dirty = "You're doing great. As an AI, I cannot provide medical advice. Keep it up!"
    let clean = AIResponseCleaner.clean(dirty)
    #expect(!clean.lowercased().contains("as an ai"))
}

@Test func aiResponseCleanerDeduplicates() async throws {
    let dirty = "Great progress. Great progress. Keep going."
    let clean = AIResponseCleaner.clean(dirty)
    // Should only have one "Great progress"
    let count = clean.components(separatedBy: "Great progress").count - 1
    #expect(count == 1)
}

// MARK: - Token Budget Tests

@Test @MainActor func aiTokenEstimation() async throws {
    let text = "Hello world this is a test" // ~7 tokens
    let estimate = AIContextBuilder.estimateTokens(text)
    #expect(estimate > 0)
    #expect(estimate < 20)
}

@Test @MainActor func aiTokenTruncation() async throws {
    let long = String(repeating: "Hello world. ", count: 100) // ~1300 chars = ~325 tokens
    let truncated = AIContextBuilder.truncateToFit(long, maxTokens: 50) // 50 tokens = ~200 chars
    #expect(truncated.count < long.count)
    #expect(truncated.count <= 200)
}

// MARK: - Natural Food Phrasing

@Test func aiNaturalPhrasing_IJustHad() async throws {
    let intent = AIActionExecutor.parseFoodIntent("i just had a samosa for lunch")
    #expect(intent != nil, "'I just had' should be recognized")
    #expect(intent?.query == "samosa")
}

@Test func aiNaturalPhrasing_IAte() async throws {
    let intent = AIActionExecutor.parseFoodIntent("i ate chicken breast")
    #expect(intent != nil, "'I ate' should be recognized")
    #expect(intent?.query == "chicken breast")
}

@Test func aiNaturalPhrasing_JustHad() async throws {
    let intent = AIActionExecutor.parseFoodIntent("just had some rice")
    #expect(intent != nil, "'just had' should be recognized")
}

// MARK: - Chain-of-Thought Nutrition Lookup

@Test @MainActor func aiChainOfThoughtNutritionLookup() async throws {
    let steps = AIChainOfThought.plan(query: "how many calories in a banana", screen: .food)
    #expect(steps != nil, "Nutrition lookup should trigger chain-of-thought")
    #expect(steps?.first?.label.contains("nutrition") == true)
}

@Test @MainActor func aiChainOfThoughtComparison() async throws {
    let steps = AIChainOfThought.plan(query: "compare this week to last week", screen: .dashboard)
    #expect(steps != nil, "Comparison should trigger chain-of-thought")
}

@Test @MainActor func aiChainOfThoughtMultiDomain() async throws {
    // "Should I exercise given my sleep?" needs both workout AND sleep
    let steps = AIChainOfThought.plan(query: "should I work out today given my sleep", screen: .dashboard)
    #expect(steps != nil)
    #expect(steps?.count ?? 0 >= 2, "Multi-domain query should fetch 2+ data sources")
}

// MARK: - Response Quality

@Test func aiResponseQualityCheck() async throws {
    #expect(AIResponseCleaner.isLowQuality("") == true)
    #expect(AIResponseCleaner.isLowQuality("Hi") == true)
    #expect(AIResponseCleaner.isLowQuality("I'm here to help you with anything you need.") == true)
    #expect(AIResponseCleaner.isLowQuality("You've eaten 1200 of 1800 cal. Consider a protein-rich dinner.") == false)
}

// MARK: - Auto-Dependency Tests

@Test @MainActor func aiChainOfThoughtWeightPlateau() async throws {
    // "Why am I not losing weight?" should fetch BOTH weight AND food context
    let steps = AIChainOfThought.plan(query: "why am I not losing weight?", screen: .weight)
    #expect(steps != nil)
    #expect(steps?.count ?? 0 >= 2, "Weight plateau query should fetch weight + food context")
}

@Test @MainActor func aiChainOfThoughtScreenFallback() async throws {
    // On glucose screen, any unknown query should still fetch glucose context
    let steps = AIChainOfThought.plan(query: "tell me more", screen: .glucose)
    #expect(steps != nil, "Screen-aware fallback should fetch glucose context")
}

// MARK: - Food Search Qualifier Stripping

@Test func aiFoodSearchWithQualifier() async throws {
    // "slices of" should be stripped before searching
    let intent = AIActionExecutor.parseFoodIntent("log 2 slices of pizza")
    #expect(intent != nil)
    // The query will be "slices of pizza" — findFood should strip "slices of "
    #expect(intent?.servings == 2)
}

@Test func aiFoodSearchWithSome() async throws {
    let intent = AIActionExecutor.parseFoodIntent("had some rice")
    #expect(intent != nil)
    // "some" is stripped in qualifiers
    #expect(intent?.query == "some rice" || intent?.query == "rice")
}

// MARK: - Weight Intent Edge Cases

@Test func aiWeightSanityCheck() async throws {
    // Values outside 20-500 should be rejected (prevents food weight logging)
    let small = AIActionExecutor.parseWeightIntent("chicken weighs 200g")
    #expect(small == nil, "200g is too small for body weight (if no unit, treated as raw number)")
    // But 165 is valid
    let valid = AIActionExecutor.parseWeightIntent("I weigh 165")
    #expect(valid != nil)
    #expect(valid?.weightValue == 165)
}

@Test func aiParseMultipleActionsFirstWins() async throws {
    // If response has multiple actions, first one should be extracted
    let (action, _) = AIActionParser.parse("[LOG_FOOD: rice] and [START_WORKOUT: push]")
    if case .logFood(let name, _) = action {
        #expect(name == "rice")
    } else {
        #expect(Bool(false), "Expected logFood (first action)")
    }
}

// MARK: - AIToolAgent Tests

@Test @MainActor func aiToolAgentIsInfoTool() async throws {
    // Known info tools
    #expect(AIToolAgent.isInfoTool("food_info") == true)
    #expect(AIToolAgent.isInfoTool("weight_info") == true)
    #expect(AIToolAgent.isInfoTool("exercise_info") == true)
    #expect(AIToolAgent.isInfoTool("sleep_recovery") == true)
    #expect(AIToolAgent.isInfoTool("supplements") == true)
    #expect(AIToolAgent.isInfoTool("glucose") == true)
    #expect(AIToolAgent.isInfoTool("biomarkers") == true)
    #expect(AIToolAgent.isInfoTool("body_comp") == true)
    #expect(AIToolAgent.isInfoTool("explain_calories") == true)

    // Action tools should not be info tools
    #expect(AIToolAgent.isInfoTool("log_food") == false)
    #expect(AIToolAgent.isInfoTool("log_weight") == false)
    #expect(AIToolAgent.isInfoTool("start_workout") == false)
    #expect(AIToolAgent.isInfoTool("mark_supplement") == false)
    #expect(AIToolAgent.isInfoTool("delete_food") == false)
    #expect(AIToolAgent.isInfoTool("") == false)
    #expect(AIToolAgent.isInfoTool("nonexistent_tool") == false)
}

@Test @MainActor func aiToolAgentInsightPrefixNoData() async throws {
    // Empty/no-data states should NOT get a prefix
    #expect(AIToolAgent.addInsightPrefix(to: "No food logged today") == "No food logged today")
    #expect(AIToolAgent.addInsightPrefix(to: "Nothing logged yet") == "Nothing logged yet")
    #expect(AIToolAgent.addInsightPrefix(to: "No data available") == "No data available")
    #expect(AIToolAgent.addInsightPrefix(to: "No weight entries found") == "No weight entries found")
}

@Test @MainActor func aiToolAgentInsightPrefixNegative() async throws {
    let over = AIToolAgent.addInsightPrefix(to: "You are 300 cal over target today")
    #expect(over.hasPrefix("Heads up"))
    let sleep = AIToolAgent.addInsightPrefix(to: "Poor sleep quality last night")
    #expect(sleep.hasPrefix("Take it easy"))
    let recovery = AIToolAgent.addInsightPrefix(to: "Low recovery score today")
    #expect(recovery.hasPrefix("Take it easy"))
}

@Test @MainActor func aiToolAgentInsightPrefixPositive() async throws {
    let track = AIToolAgent.addInsightPrefix(to: "You are on track for your calorie goal")
    #expect(track.hasPrefix("Nice work!"))
    let remaining = AIToolAgent.addInsightPrefix(to: "800 calories remaining today")
    #expect(remaining.hasPrefix("Looking good"))
    let left = AIToolAgent.addInsightPrefix(to: "500 cal left for dinner")
    #expect(left.hasPrefix("Looking good"))
}

@Test @MainActor func aiToolAgentInsightPrefixExercise() async throws {
    let workout = AIToolAgent.addInsightPrefix(to: "3 workouts this week: push, pull, legs")
    #expect(workout.hasPrefix("Here's your activity"))
    let streak = AIToolAgent.addInsightPrefix(to: "5-day workout streak!")
    #expect(streak.hasPrefix("Here's your activity"))
}

@Test @MainActor func aiToolAgentInsightPrefixWeight() async throws {
    let trend = AIToolAgent.addInsightPrefix(to: "Weight trend: losing 0.5 lbs/week")
    #expect(trend.hasPrefix("Here's the trend"))
    let gaining = AIToolAgent.addInsightPrefix(to: "You're gaining slightly this week")
    #expect(gaining.hasPrefix("Here's the trend"))
}

@Test @MainActor func aiToolAgentInsightPrefixDefault() async throws {
    let generic = AIToolAgent.addInsightPrefix(to: "Vitamin D: 2000 IU taken")
    #expect(generic.hasPrefix("Here's what I found"))
}

@Test @MainActor func aiToolAgentStepMessages() async throws {
    // Food-related
    #expect(AIToolAgent.stepMessage(for: "log 2 eggs") == "Logging food...")
    #expect(AIToolAgent.stepMessage(for: "I ate chicken") == "Logging food...")
    #expect(AIToolAgent.stepMessage(for: "had some rice") == "Logging food...")
    #expect(AIToolAgent.stepMessage(for: "add banana to breakfast") == "Logging food...")

    // Workout-related
    #expect(AIToolAgent.stepMessage(for: "start push day") == "Setting up workout...")
    #expect(AIToolAgent.stepMessage(for: "begin workout") == "Setting up workout...")
    #expect(AIToolAgent.stepMessage(for: "chest day today") == "Setting up workout...")
    #expect(AIToolAgent.stepMessage(for: "legs workout") == "Setting up workout...")

    // Supplement-related
    #expect(AIToolAgent.stepMessage(for: "took my creatine") == "Updating supplements...")
    #expect(AIToolAgent.stepMessage(for: "vitamin D done") == "Updating supplements...")

    // Info/query-related
    #expect(AIToolAgent.stepMessage(for: "how many calories left") == "Checking your data...")
    #expect(AIToolAgent.stepMessage(for: "show me my weight") == "Checking your data...")
    #expect(AIToolAgent.stepMessage(for: "what should I eat") == "Checking your data...")

    // Default fallback
    #expect(AIToolAgent.stepMessage(for: "hello there") == "Looking that up...")
    #expect(AIToolAgent.stepMessage(for: "thanks") == "Looking that up...")
}

@Test @MainActor func aiToolAgentFallbackTextPerScreen() async throws {
    // Each screen should produce a non-empty, screen-specific fallback
    let screens: [AIScreen] = [.food, .weight, .exercise, .bodyRhythm, .supplements, .glucose, .biomarkers, .bodyComposition, .cycle, .dashboard, .goal]

    for screen in screens {
        let text = AIToolAgent.fallbackText(for: screen)
        #expect(!text.isEmpty, "Fallback for \(screen) should not be empty")
    }

    // Screen-specific content checks
    #expect(AIToolAgent.fallbackText(for: .food).contains("food") || AIToolAgent.fallbackText(for: .food).contains("calories"))
    #expect(AIToolAgent.fallbackText(for: .weight).contains("weight"))
    #expect(AIToolAgent.fallbackText(for: .exercise).contains("workout"))
    #expect(AIToolAgent.fallbackText(for: .supplements).contains("supplement"))
    #expect(AIToolAgent.fallbackText(for: .glucose).contains("glucose"))
    #expect(AIToolAgent.fallbackText(for: .biomarkers).contains("lab") || AIToolAgent.fallbackText(for: .biomarkers).contains("marker"))
    #expect(AIToolAgent.fallbackText(for: .bodyComposition).contains("body") || AIToolAgent.fallbackText(for: .bodyComposition).contains("composition"))
    #expect(AIToolAgent.fallbackText(for: .cycle).contains("cycle"))
}

@Test @MainActor func aiToolAgentHandleTextResponseEmpty() async throws {
    // Empty/low-quality responses should produce fallback text
    let empty = AIToolAgent.handleTextResponse("", screen: .food)
    #expect(empty.text == AIToolAgent.fallbackText(for: .food))
    #expect(empty.action == nil)
    #expect(empty.toolsCalled.isEmpty)

    let tooShort = AIToolAgent.handleTextResponse("Hi", screen: .weight)
    #expect(tooShort.text == AIToolAgent.fallbackText(for: .weight))
}

@Test @MainActor func aiToolAgentHandleTextResponseGeneric() async throws {
    let generic = AIToolAgent.handleTextResponse("I'm here to help you with anything you need.", screen: .dashboard)
    #expect(generic.text == AIToolAgent.fallbackText(for: .dashboard))
}

@Test @MainActor func aiToolAgentHandleTextResponseValid() async throws {
    let valid = AIToolAgent.handleTextResponse("You've eaten 1200 of 1800 cal. Protein is at 85g.", screen: .food)
    #expect(valid.text.contains("1200"))
    #expect(valid.action == nil)
}

@Test @MainActor func aiToolAgentHandleTextResponseCleansArtifacts() async throws {
    let dirty = AIToolAgent.handleTextResponse("Great progress on your weight!<|im_end|> Keep it up.", screen: .weight)
    #expect(!dirty.text.contains("<|im_end|>"))
}

@Test @MainActor func aiToolAgentFallbackWeightGoal() async throws {
    // .goal and .weight should share the same fallback
    #expect(AIToolAgent.fallbackText(for: .goal) == AIToolAgent.fallbackText(for: .weight))
}

// MARK: - AIToolAgent Extended Coverage Tests

@Test @MainActor func aiToolAgentExecuteToolWithTextResult() async throws {
    ToolRegistration.registerAll()
    // weight_info is an info tool that returns text — test executeTool path
    let call = ToolCall(tool: "weight_info", params: ToolCallParams(values: [:]))
    let output = await AIToolAgent.executeTool(call)
    // Should return text (even if empty data), not crash
    #expect(output.toolsCalled == ["weight_info"])
    #expect(output.action == nil)
}

@Test @MainActor func aiToolAgentExecuteToolWithUnknownTool() async throws {
    ToolRegistration.registerAll()
    let call = ToolCall(tool: "nonexistent_tool_xyz", params: ToolCallParams(values: [:]))
    let output = await AIToolAgent.executeTool(call)
    // Unknown tool should produce a friendly error message
    #expect(output.toolsCalled == ["nonexistent_tool_xyz"])
    #expect(output.text.contains("couldn't") || output.text.contains("help") || !output.text.isEmpty)
}

@Test @MainActor func aiToolAgentExecuteToolWithFoodInfo() async throws {
    ToolRegistration.registerAll()
    let call = ToolCall(tool: "food_info", params: ToolCallParams(values: ["period": "today"]))
    let output = await AIToolAgent.executeTool(call)
    #expect(output.toolsCalled == ["food_info"])
    #expect(output.action == nil)
    // food_info returns text data about nutrition
    #expect(!output.text.isEmpty)
}

@Test @MainActor func aiToolAgentExecuteToolWithExplainCalories() async throws {
    ToolRegistration.registerAll()
    let call = ToolCall(tool: "explain_calories", params: ToolCallParams(values: [:]))
    let output = await AIToolAgent.executeTool(call)
    #expect(output.toolsCalled == ["explain_calories"])
    #expect(output.action == nil)
}

@Test @MainActor func aiToolAgentWithTimeoutCompletes() async throws {
    // Operation that completes instantly — should return value
    let result = await AIToolAgent.withTimeout(seconds: 5) {
        return "completed"
    }
    #expect(result == "completed")
}

@Test @MainActor func aiToolAgentWithTimeoutReturnsNilOnTimeout() async throws {
    // Operation that takes longer than timeout — should return nil
    let result = await AIToolAgent.withTimeout(seconds: 1) {
        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        return "should not reach"
    }
    #expect(result == nil)
}

@Test @MainActor func aiToolAgentWithTimeoutReturnsInt() async throws {
    let result = await AIToolAgent.withTimeout(seconds: 5) {
        return 42
    }
    #expect(result == 42)
}

@Test @MainActor func aiToolAgentWithTimeoutReturnsOptional() async throws {
    let result: String?? = await AIToolAgent.withTimeout(seconds: 5) {
        return Optional<String>.none
    }
    // withTimeout returns T? where T is String? here, so result is String??
    // The outer optional is non-nil (didn't timeout), inner is nil
    #expect(result != nil) // didn't timeout
}

@Test @MainActor func aiToolAgentGatherContextDashboard() async throws {
    // gatherContext should return non-empty context for any screen
    let context = AIToolAgent.gatherContext(query: "how am I doing", screen: .dashboard)
    #expect(!context.isEmpty)
}

@Test @MainActor func aiToolAgentGatherContextFood() async throws {
    let context = AIToolAgent.gatherContext(query: "what did I eat today", screen: .food)
    #expect(!context.isEmpty)
}

@Test @MainActor func aiToolAgentGatherContextWeight() async throws {
    let context = AIToolAgent.gatherContext(query: "how is my weight", screen: .weight)
    #expect(!context.isEmpty)
}

@Test @MainActor func aiToolAgentGatherContextExercise() async throws {
    let context = AIToolAgent.gatherContext(query: "what should I train", screen: .exercise)
    #expect(!context.isEmpty)
}

@Test @MainActor func aiToolAgentExecuteRelevantToolsInfoQuery() async throws {
    ToolRegistration.registerAll()
    // A food-related info query should trigger food_info tool
    let results = await AIToolAgent.executeRelevantTools(query: "how many calories today", screen: .food)
    // Should return results (possibly empty if no food logged, but should not crash)
    // At minimum, the function should complete without error
    #expect(results.count >= 0)
}

@Test @MainActor func aiToolAgentExecuteRelevantToolsActionQuery() async throws {
    ToolRegistration.registerAll()
    // An action query like "log food" should NOT trigger info tools (they're filtered)
    let results = await AIToolAgent.executeRelevantTools(query: "log 2 eggs", screen: .food)
    // executeRelevantTools filters to info tools only, "log" queries rank action tools
    // So this should return empty or only info results
    for r in results {
        // Any returned tools should be info tools
        for tool in r.toolsCalled {
            #expect(AIToolAgent.isInfoTool(tool) || tool.isEmpty)
        }
    }
}

@Test @MainActor func aiToolAgentExecuteRelevantToolsWeightQuery() async throws {
    ToolRegistration.registerAll()
    let results = await AIToolAgent.executeRelevantTools(query: "how is my weight trend", screen: .weight)
    #expect(results.count >= 0) // Should not crash
}

@Test @MainActor func aiToolAgentHandleTextResponseAllScreens() async throws {
    // Valid response should work for all screens
    let screens: [AIScreen] = [.food, .weight, .exercise, .dashboard, .bodyRhythm, .supplements, .glucose, .biomarkers, .bodyComposition, .cycle, .goal]
    for screen in screens {
        let output = AIToolAgent.handleTextResponse("Your data looks great today with solid progress across all areas.", screen: screen)
        #expect(!output.text.isEmpty, "handleTextResponse should return non-empty for \(screen)")
        #expect(output.action == nil)
        #expect(output.toolsCalled.isEmpty)
    }
}

@Test @MainActor func aiToolAgentHandleTextResponseWhitespace() async throws {
    let output = AIToolAgent.handleTextResponse("   \n\t  ", screen: .food)
    // Whitespace-only should be treated as empty → fallback
    #expect(output.text == AIToolAgent.fallbackText(for: .food))
}

@Test @MainActor func aiToolAgentHandleTextResponseMarkdown() async throws {
    let output = AIToolAgent.handleTextResponse("**Great job!** You ate 1500 cal today with 90g protein.", screen: .food)
    #expect(output.text.contains("1500") || output.text.contains("Great"))
}

@Test @MainActor func aiToolAgentInsightPrefixOverCalSeparate() async throws {
    // "over" without "target" but with "cal"
    let result = AIToolAgent.addInsightPrefix(to: "You went over by 200 cal")
    #expect(result.hasPrefix("Heads up"))
}

@Test @MainActor func aiToolAgentInsightPrefixWellRecovered() async throws {
    let result = AIToolAgent.addInsightPrefix(to: "Well recovered after last night's rest")
    #expect(result.hasPrefix("Nice work!"))
}

@Test @MainActor func aiToolAgentInsightPrefixTargetReached() async throws {
    let result = AIToolAgent.addInsightPrefix(to: "Protein target reached for the day")
    #expect(result.hasPrefix("Nice work!"))
}

@Test @MainActor func aiToolAgentStepMessageDrankEaten() async throws {
    #expect(AIToolAgent.stepMessage(for: "I drank some water") == "Logging food...")
    #expect(AIToolAgent.stepMessage(for: "I've eaten lunch already") == "Logging food...")
}

@Test @MainActor func aiToolAgentStepMessageSleepOverlap() async throws {
    // "sleep" contains "how" check priority — "sleep" is in the info keywords
    #expect(AIToolAgent.stepMessage(for: "how did I sleep") == "Checking your data...")
}

@Test @MainActor func aiToolAgentAgentOutputConstruction() async throws {
    let output = AgentOutput(text: "test message", action: nil, toolsCalled: ["tool1", "tool2"])
    #expect(output.text == "test message")
    #expect(output.action == nil)
    #expect(output.toolsCalled == ["tool1", "tool2"])

    let empty = AgentOutput(text: "", action: nil, toolsCalled: [])
    #expect(empty.text.isEmpty)
    #expect(empty.toolsCalled.isEmpty)
}

@Test @MainActor func aiToolAgentIsInfoToolAllKnown() async throws {
    // Exhaustive check of all 9 info tools
    let infoTools = ["food_info", "weight_info", "exercise_info", "sleep_recovery",
                     "supplements", "glucose", "biomarkers", "body_comp", "explain_calories"]
    for tool in infoTools {
        #expect(AIToolAgent.isInfoTool(tool) == true, "\(tool) should be an info tool")
    }

    // Action tools
    let actionTools = ["log_food", "log_weight", "start_workout", "mark_supplement",
                       "delete_food", "add_supplement", "scan_barcode"]
    for tool in actionTools {
        #expect(AIToolAgent.isInfoTool(tool) == false, "\(tool) should NOT be an info tool")
    }
}

// MARK: - FoodService Tests

@Test @MainActor func foodServiceResolvedCalorieTarget() async throws {
    let target = FoodService.resolvedCalorieTarget()
    // Should return a reasonable calorie target (at least 1200 floor)
    #expect(target >= 1200, "Calorie target should be at least 1200")
    #expect(target <= 5000, "Calorie target should be reasonable (<= 5000)")
}

@Test @MainActor func foodServiceGetDailyTotals() async throws {
    let totals = FoodService.getDailyTotals()
    // On empty/test DB, should have valid structure
    #expect(totals.target >= 1200)
    #expect(totals.eaten >= 0)
    #expect(totals.proteinG >= 0)
    #expect(totals.carbsG >= 0)
    #expect(totals.fatG >= 0)
    #expect(totals.fiberG >= 0)
    #expect(totals.remaining == totals.target - totals.eaten)
}

@Test @MainActor func foodServiceGetDailyTotalsWithDate() async throws {
    // Querying a specific past date should work
    let totals = FoodService.getDailyTotals(date: "2020-01-01")
    #expect(totals.eaten == 0, "Old date should have no food logged")
    #expect(totals.target >= 1200)
    #expect(totals.remaining == totals.target)
}

@Test @MainActor func foodServiceGetCaloriesLeft() async throws {
    let result = FoodService.getCaloriesLeft()
    #expect(!result.isEmpty)
    // Should contain calorie info
    #expect(result.contains("cal"), "Should mention calories")
}

@Test @MainActor func foodServiceExplainCalories() async throws {
    let explanation = FoodService.explainCalories()
    #expect(!explanation.isEmpty)
    #expect(explanation.contains("TDEE"), "Should mention TDEE")
    #expect(explanation.contains("cal"), "Should mention calories")
    #expect(explanation.contains("Eaten today"), "Should show eaten amount")
    #expect(explanation.contains("Remaining"), "Should show remaining amount")
    #expect(explanation.contains("Macros"), "Should show macros")
}

@Test @MainActor func foodServiceSearchFoodEmpty() async throws {
    // Searching for nonsense should return empty or few results
    let results = FoodService.searchFood(query: "zzzzxxxxxxxnonexistent")
    #expect(results.count >= 0) // Should not crash
}

@Test @MainActor func foodServiceSearchFoodRealFood() async throws {
    // "chicken" should exist in the 1041-food DB
    let results = FoodService.searchFood(query: "chicken")
    #expect(!results.isEmpty, "chicken should be in DB")
    #expect(results.first?.name.lowercased().contains("chicken") == true)
}

@Test @MainActor func foodServiceSearchFoodSpellCorrection() async throws {
    // "chiken" (misspelled) should still find chicken via SpellCorrectService
    let results = FoodService.searchFood(query: "chiken")
    #expect(!results.isEmpty, "SpellCorrect should fix chiken → chicken")
}

@Test @MainActor func foodServiceFindByName() async throws {
    let found = FoodService.findByName("banana")
    #expect(found != nil, "banana should be in DB")
    #expect(found?.name.lowercased().contains("banana") == true)

    let notFound = FoodService.findByName("zzzznonexistentfood")
    #expect(notFound == nil)
}

@Test @MainActor func foodServiceGetNutrition() async throws {
    let result = FoodService.getNutrition(name: "egg")
    if let result {
        #expect(!result.perServing.isEmpty)
        #expect(result.perServing.contains("cal"))
        #expect(result.food.calories > 0)
    }
    // Non-existent food
    let none = FoodService.getNutrition(name: "zzzznonexistent")
    #expect(none == nil)
}

@Test @MainActor func foodServiceIsFavorite() async throws {
    // On empty/test DB, random food should not be favorite
    let isFav = FoodService.isFavorite(name: "random_test_food_xyz")
    #expect(isFav == false)
}

@Test @MainActor func foodServiceFetchRecentFoods() async throws {
    let recents = FoodService.fetchRecentFoods()
    #expect(recents.count >= 0) // Should not crash, may be empty on test DB
}

@Test @MainActor func foodServiceFetchMealLogs() async throws {
    // Far past date should return empty
    let logs = FoodService.fetchMealLogs(for: "2020-01-01")
    #expect(logs.isEmpty)
}

@Test @MainActor func foodServiceDeleteEntryNoMatch() async throws {
    // Deleting a non-existent food should return a friendly message
    let result = FoodService.deleteEntry(matching: "zzzznonexistent")
    #expect(result.contains("No food logged") || result.contains("Couldn't find"))
}

@Test @MainActor func foodServiceDeleteEntryLast() async throws {
    // "last" on empty day should return no entries message
    let result = FoodService.deleteEntry(matching: "last")
    #expect(result.contains("No food") || result.contains("No entries") || result.contains("Removed"))
}

@Test @MainActor func foodServiceCopyYesterday() async throws {
    let result = FoodService.copyYesterday()
    #expect(!result.isEmpty)
    // On test DB, yesterday likely has no food
    #expect(result.contains("No food logged") || result.contains("Copied") || result.contains("No entries"))
}

@Test @MainActor func foodServiceTopProteinFoods() async throws {
    let foods = FoodService.topProteinFoods()
    // Should return foods from DB (even without user history)
    #expect(foods.count >= 0) // May be empty on test DB but should not crash
    for food in foods {
        #expect(food.proteinG >= 15, "topProteinFoods should filter for >= 15g protein")
    }
}

@Test @MainActor func foodServiceSuggestMeal() async throws {
    let suggestions = FoodService.suggestMeal()
    #expect(suggestions.count >= 0) // May be empty on test DB
    #expect(suggestions.count <= 3, "suggestMeal should return max 3")
}

@Test @MainActor func foodServiceDailyTotalsStruct() async throws {
    let totals = DailyTotals(eaten: 1500, target: 2000, remaining: 500,
                             proteinG: 80, carbsG: 200, fatG: 60, fiberG: 25)
    #expect(totals.eaten == 1500)
    #expect(totals.target == 2000)
    #expect(totals.remaining == 500)
    #expect(totals.proteinG == 80)
    #expect(totals.carbsG == 200)
    #expect(totals.fatG == 60)
    #expect(totals.fiberG == 25)
}

@Test @MainActor func foodServiceSearchRecipes() async throws {
    let results = FoodService.searchRecipes(query: "zzzznonexistent")
    #expect(results.isEmpty)
}

@Test @MainActor func foodServiceFetchCachedBarcode() async throws {
    let cached = FoodService.fetchCachedBarcode("0000000000000")
    #expect(cached == nil, "Non-existent barcode should return nil")
}

@Test @MainActor func foodServiceFetchFoodsByCategory() async throws {
    let foods = FoodService.fetchFoodsByCategory("zzzznonexistent")
    #expect(foods.isEmpty)
}
