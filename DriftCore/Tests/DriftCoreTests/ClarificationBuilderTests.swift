import Foundation
@testable import DriftCore
import Testing

/// Ask-don't-guess: deterministic ambiguity detection. #226.
/// Covers ambiguous triggers (must produce options) AND unambiguous
/// negatives (must stay silent). The negative set is the regression floor
/// — if any of these grow options, FoodLoggingGoldSet will regress.

// MARK: - Bare food noun

@Test func bareFoodNounOffersLogAndInfoOptions() {
    guard let opts = ClarificationBuilder.buildOptions(for: "chicken") else {
        Issue.record("expected options for bare food noun"); return
    }
    #expect(opts.count == 2)
    #expect(opts[0].tool == "log_food")
    #expect(opts[0].params["name"] == "chicken")
    #expect(opts[1].tool == "food_info")
    #expect(opts[1].params["query"]?.contains("chicken") == true)
}

@Test func bareFoodNounVarietyAllTrigger() {
    let bareFoods = ["biryani", "paneer", "banana", "coffee", "salmon", "tofu"]
    for food in bareFoods {
        guard let opts = ClarificationBuilder.buildOptions(for: food) else {
            Issue.record("expected options for '\(food)'"); continue
        }
        #expect(opts.count == 2, "\(food): want 2 options")
        #expect(opts.first?.tool == "log_food")
    }
}

// MARK: - Bare supplement

@Test func bareSupplementNounOffersMarkAndStatus() {
    guard let opts = ClarificationBuilder.buildOptions(for: "creatine") else {
        Issue.record("expected options for supplement"); return
    }
    #expect(opts.count == 2)
    #expect(opts[0].tool == "mark_supplement")
    #expect(opts[0].params["name"] == "creatine")
    #expect(opts[1].tool == "supplements")
}

@Test func bareSupplementMultiwordTriggers() {
    guard let opts = ClarificationBuilder.buildOptions(for: "vitamin d") else {
        Issue.record("expected options for 'vitamin d'"); return
    }
    #expect(opts.count == 2)
    #expect(opts[0].tool == "mark_supplement")
}

// MARK: - Bare weight value

@Test func bareWeightValueOffersKgLbsAndGoal() {
    guard let opts = ClarificationBuilder.buildOptions(for: "150") else {
        Issue.record("expected options for bare number"); return
    }
    #expect(opts.count == 3)
    #expect(opts[0].tool == "log_weight")
    #expect(opts[0].params["unit"] == "lbs")
    #expect(opts[1].tool == "log_weight")
    #expect(opts[1].params["unit"] == "kg")
    #expect(opts[2].tool == "set_goal")
}

@Test func numbersOutsideWeightRangeDontTrigger() {
    #expect(ClarificationBuilder.buildOptions(for: "5") == nil)
    #expect(ClarificationBuilder.buildOptions(for: "1000") == nil)
    #expect(ClarificationBuilder.buildOptions(for: "19") == nil)
}

// MARK: - Ambiguous log verb

@Test func logCardioAmbiguityTriggers() {
    guard let opts = ClarificationBuilder.buildOptions(for: "log rowing") else {
        Issue.record("expected options for 'log rowing'"); return
    }
    #expect(opts.count == 2)
    #expect(opts.contains(where: { $0.tool == "log_food" }))
    #expect(opts.contains(where: { $0.tool == "log_activity" }))
}

// MARK: - Negative cases (must stay silent)

@Test func clearFoodLoggingDoesNotTrigger() {
    let clearCases = [
        "log 2 eggs", "log pizza", "ate biryani", "i had chicken",
        "log biryani", "add salad"
    ]
    for msg in clearCases {
        #expect(ClarificationBuilder.buildOptions(for: msg) == nil,
            "'\(msg)' should not trigger clarifier")
    }
}

@Test func explicitFoodInfoDoesNotTrigger() {
    let infoCases = [
        "calories in banana", "calories in chicken", "how many calories in rice",
        "protein in egg", "carbs in toast"
    ]
    for msg in infoCases {
        #expect(ClarificationBuilder.buildOptions(for: msg) == nil,
            "'\(msg)' should not trigger clarifier")
    }
}

@Test func greetingsAndBareVerbsDoNotTrigger() {
    let inputs = ["hi", "hello", "thanks", "help", "log", "add",
                  "what should I eat", "daily summary"]
    for msg in inputs {
        #expect(ClarificationBuilder.buildOptions(for: msg) == nil,
            "'\(msg)' should not trigger clarifier")
    }
}

@Test func domainQueriesDoNotTrigger() {
    let inputs = [
        "weight trend", "how did i sleep", "calories left",
        "daily summary", "my hrv today", "did i take vitamin d"
    ]
    for msg in inputs {
        #expect(ClarificationBuilder.buildOptions(for: msg) == nil,
            "'\(msg)' should not trigger clarifier")
    }
}

@Test func longMessagesDoNotTrigger() {
    // 60+ char guard — typical long queries are expressive enough to classify.
    let long = "I want to know everything about my meal breakdown for the week"
    #expect(ClarificationBuilder.buildOptions(for: long) == nil)
}

@Test func emptyInputDoesNotTrigger() {
    #expect(ClarificationBuilder.buildOptions(for: "") == nil)
    #expect(ClarificationBuilder.buildOptions(for: "   ") == nil)
}

// MARK: - Prompt formatting

@Test func promptTextNumbersAllOptions() {
    let opts: [ClarificationOption] = [
        .init(id: 1, label: "Log chicken as food", tool: "log_food", params: ["name": "chicken"]),
        .init(id: 2, label: "Look up calories in chicken", tool: "food_info", params: ["query": "calories in chicken"])
    ]
    let text = ClarificationBuilder.promptText(opts)
    #expect(text.contains("1. Log chicken as food"))
    #expect(text.contains("2. Look up calories in chicken"))
    #expect(text.contains("Did you mean"))
    #expect(text.contains("nevermind"))
}

// MARK: - Codable roundtrip (Phase case)

@Test func clarificationOptionRoundtripsCodable() throws {
    let original: [ClarificationOption] = [
        .init(id: 1, label: "Log chicken as food", tool: "log_food", params: ["name": "chicken"]),
        .init(id: 2, label: "Look up calories", tool: "food_info", params: ["query": "calories in chicken"])
    ]
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode([ClarificationOption].self, from: data)
    #expect(decoded == original)
}

@Test @MainActor func phaseAwaitingClarificationRoundtrips() throws {
    let opts: [ClarificationOption] = [
        .init(id: 1, label: "Mark creatine as taken", tool: "mark_supplement", params: ["name": "creatine"]),
        .init(id: 2, label: "Check if I've taken creatine", tool: "supplements", params: ["query": "creatine"])
    ]
    let original: ConversationState.Phase = .awaitingClarification(options: opts)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ConversationState.Phase.self, from: data)
    #expect(decoded == original)
}

@Test @MainActor func resumeBlurbHasEntryForClarification() {
    let phase: ConversationState.Phase = .awaitingClarification(options: [])
    #expect(phase.resumeBlurb == "that clarification")
}
