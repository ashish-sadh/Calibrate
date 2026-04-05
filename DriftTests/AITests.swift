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
    #expect(context.contains("food") || context.contains("No") || context.contains("Target"))
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
