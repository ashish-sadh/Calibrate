import Foundation
@testable import DriftCore
import Testing

// Tier-0 tests for #823 FoundationModelsFoodExtractor — the public facade
// over FoodLogIntentExtractor wired into VoiceLogSheet. Pure helpers only;
// real-FM golden coverage lives in
// DriftLLMEvalMacOS/FoundationModelsFoodExtractorIndianEval.swift (Tier-3).

// Flag-off kill-switch tests live in FoodLogIntentExtractorTests.swift's
// FoodIntentFlagBehavior suite — same UserDefaults key, must serialize against
// each other. Splitting them across two sibling @Suite(.serialized) structs
// flaked because Swift Testing parallelizes ACROSS suites.

// MARK: - Prompt anchoring (delegates through; pins that the facade does not
// silently strip the safety guards the underlying extractor depends on)

@Test func extractorPromptCoversMultiItem() {
    // Multi-item parse is the headline capability for VoiceLogSheet —
    // pin the prompt content the FM sees so the additionalItems pathway
    // can't silently regress.
    let p = FoundationModelsFoodExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("additionalitems") || p.contains("multi-food"))
}

@Test func extractorPromptCoversNonFoodSentinel() {
    let p = FoundationModelsFoodExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("empty"))
}

@Test func extractorPromptCoversGreetings() {
    // Real-field bug (2026-05-21): "Hello how are you doing" hallucinated
    // egg + banana. The facade must surface the same greeting guardrails.
    let p = FoundationModelsFoodExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("hello"))
    #expect(p.contains("how are you"))
}

@Test func extractorPromptIncludesInputText() {
    let unique = "MARKER_\(UUID().uuidString.prefix(8))"
    let p = FoundationModelsFoodExtractor.buildPrompt(for: unique)
    #expect(p.contains(unique))
}

@Test func extractorPromptCoversCountWeightVolume() {
    let p = FoundationModelsFoodExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("pieces"))
    #expect(p.contains("grams"))
    #expect(p.contains("cup") || p.contains("cups"))
}

// MARK: - Candidate type alias contract

@Test func candidateAliasMatchesFMItem() {
    // The `Candidate` typealias must stay pinned to FMFoodLogIntent.Item
    // so a future internal rename doesn't silently break VoiceLogSheet.
    let raw = FMFoodLogIntent.Item(foodName: "egg", quantity: 2, unit: .pieces)
    let alias: FoundationModelsFoodExtractor.Candidate = raw
    #expect(alias.foodName == "egg")
    #expect(alias.quantity == 2)
    #expect(alias.unit == .pieces)
}
