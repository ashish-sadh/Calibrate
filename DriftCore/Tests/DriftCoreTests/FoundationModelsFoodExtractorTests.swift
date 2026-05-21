import Foundation
@testable import DriftCore
import Testing

// Tier-0 tests for #823 FoundationModelsFoodExtractor — the public facade
// over FoodLogIntentExtractor wired into VoiceLogSheet. Pure helpers only;
// real-FM golden coverage lives in
// DriftLLMEvalMacOS/FoundationModelsFoodExtractorIndianEval.swift (Tier-3).

// MARK: - Flag-off fallback (kill-switch guarantee)

@Suite(.serialized) struct FoundationModelsFoodExtractorFlagBehavior {
    private let key = "drift_fm_food_intent_extract"

    @Test func flagOffThrowsUnavailableOnCandidates() async {
        defer { UserDefaults.standard.removeObject(forKey: key) }
        Preferences.fmFoodIntentExtractEnabled = false

        await #expect(throws: FMFoodLogIntentExtractorError.self) {
            _ = try await FoundationModelsFoodExtractor.extractCandidates(text: "ate 2 eggs")
        }

        do {
            _ = try await FoundationModelsFoodExtractor.extractCandidates(text: "ate 2 eggs")
            Issue.record("Expected .unavailable when flag is off")
        } catch FMFoodLogIntentExtractorError.unavailable {
            // Expected — flag-off must short-circuit BEFORE touching the
            // FoundationModels session so iOS<26 hosts never see the
            // @available error.
        } catch {
            Issue.record("Expected .unavailable, got \(error)")
        }
    }

    @Test func flagOffThrowsUnavailableOnExtract() async {
        // The mealType-preserving `extract(text:)` overload — used by
        // VoiceLogSheet so meal hints ("for breakfast") aren't lost when
        // routing through the facade — shares the same kill-switch. Without
        // this test, a future refactor could regress only one of the two
        // surfaces and the iOS<26 fallback would break silently.
        defer { UserDefaults.standard.removeObject(forKey: key) }
        Preferences.fmFoodIntentExtractEnabled = false

        do {
            _ = try await FoundationModelsFoodExtractor.extract(text: "ate 2 eggs for breakfast")
            Issue.record("Expected .unavailable when flag is off")
        } catch FMFoodLogIntentExtractorError.unavailable {
            // Expected.
        } catch {
            Issue.record("Expected .unavailable, got \(error)")
        }
    }
}

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
