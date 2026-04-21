import Foundation
import Testing
@testable import Drift

// MARK: - Model Parity Eval (#286)
//
// Tier 0/1 queries are handled BEFORE any LLM by `InputNormalizer` + `StaticOverrides`.
// They MUST be model-agnostic — SmolLM users (Tier small, 6GB devices) and Gemma 4
// users (Tier large, 8GB+ devices) get identical deterministic behavior on these queries.
//
// Three invariants:
//   1. Coverage   — curated Tier 0/1 queries MUST hit StaticOverrides.match so the LLM
//                   is never consulted regardless of which model is loaded.
//   2. Fallthrough — queries that MUST reach the LLM (food/weight/exercise logging,
//                   info queries) MUST NOT match StaticOverrides; otherwise they'd
//                   bypass the LLM and lose personalization.
//   3. Signature  — StaticOverrides.match takes a single String. No model parameter,
//                   no tier config. Deterministic and model-independent by construction.

// Queries that must short-circuit the LLM on both models.
// Chosen to avoid runtime DB dependencies (no supplement-taken: needs active supplements).
private let tier01CoverageQueries: [String] = [
    // Greetings (StaticOverrides L51)
    "hi", "hello", "hey",
    // Thanks (L57)
    "thanks", "thank you", "got it",
    // Help (L63)
    "help", "what can you do",
    // Barcode (L68)
    "scan barcode", "barcode",
    // Navigation (L75 → screenToTab L539)
    "go to food", "open weight", "show me my dashboard", "open exercise",
    // Undo (L98) — match() returns a handler; handler is NOT invoked here.
    "undo", "undo that",
    // Copy yesterday (L153) — match() returns a handler; handler is NOT invoked.
    "copy yesterday", "same as yesterday",
    // Exercise instructions (L251) — resolves against ExerciseDatabase (bundled JSON).
    "how do i do a deadlift",
    "how to squat",
]

// Queries that must reach the LLM pipeline.
private let fallthroughToLLMQueries: [String] = [
    // Food logging
    "log 2 eggs for breakfast",
    "i had oatmeal with berries",
    // Weight logging
    "i weigh 175 lbs",
    // Exercise logging (workout-set pattern forces fallthrough — L455)
    "bench press 3x10 at 135",
    // Info queries — route to AIToolAgent for LLM-presented answers
    "what did i eat yesterday",
    "how many calories have i had today",
]

// MARK: Invariant 1 — Tier 0/1 coverage

@Test @MainActor
func modelParity_tier01_queriesShortCircuitLLM() {
    var misses: [String] = []
    for query in tier01CoverageQueries {
        let normalized = InputNormalizer.normalize(query)
        if StaticOverrides.match(normalized) == nil {
            misses.append(query)
        }
    }
    #expect(misses.isEmpty,
            "Tier 0/1 queries must hit StaticOverrides so both models behave identically. Misses: \(misses)")
}

// MARK: Invariant 2 — Fallthrough to LLM

@Test @MainActor
func modelParity_llmQueriesDoNotShortCircuit() {
    var unexpectedMatches: [String] = []
    for query in fallthroughToLLMQueries {
        let normalized = InputNormalizer.normalize(query)
        if StaticOverrides.match(normalized) != nil {
            unexpectedMatches.append(query)
        }
    }
    #expect(unexpectedMatches.isEmpty,
            "These queries must flow to the LLM, not be short-circuited by StaticOverrides: \(unexpectedMatches)")
}

// MARK: Invariant 3 — Signature is model-agnostic

// Documents that StaticOverrides.match takes exactly one String — no model, no tier.
// Any regression that adds a model-branch here would have to change the signature,
// and this test would fail to compile or fail the determinism check.
@Test @MainActor
func modelParity_staticOverridesSignatureIsModelAgnostic() {
    // Compile-time: the closure below resolves only if the signature is (String) -> StaticResult?.
    let modelAgnosticMatcher: (String) -> StaticResult? = StaticOverrides.match
    let first = modelAgnosticMatcher("hi")
    let second = modelAgnosticMatcher("hi")
    // Same input yields same match presence. Handler-case results aren't directly
    // comparable (closures), but response-case results compare by text.
    #expect((first == nil) == (second == nil),
            "StaticOverrides.match must be deterministic for the same input")
    if case let .response(t1) = first, case let .response(t2) = second {
        #expect(t1 == t2)
    }
}
