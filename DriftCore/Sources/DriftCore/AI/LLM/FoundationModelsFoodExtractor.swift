import Foundation

// #823 — Public facade for Apple Foundation Models free-text food parsing.
// Mirrors `FoundationModelsExerciseExtractor` sibling shape so call sites
// reading either feel identical. Delegates to the proven
// `FoodLogIntentExtractor` underneath; this file is the stable public
// surface (and the symbol the verifier greps for).

public enum FoundationModelsFoodExtractor {

    /// One candidate from a free-text food log message. Stable
    /// `(foodName, quantity, unit)` shape that survives FM revisions —
    /// callers (Apple-Intents-style wiring) only need to know this triple,
    /// never the underlying `@Generable` schema.
    public typealias Candidate = FMFoodLogIntent.Item

    /// Extract a typed food-log intent from a free-text user message.
    ///
    /// Returns the full `FMFoodLogIntent` (primary + additionals + meal hint)
    /// — used by VoiceLogSheet and any UI surface that surfaces meal-type
    /// inference to the user. For the flat `(foodName, quantity, unit)`
    /// candidate-list shape, see `extractCandidates(text:)`.
    ///
    /// Behavior:
    /// - iOS 26+ / macOS 26+ AND `Preferences.fmFoodIntentExtractEnabled` ON
    ///   → routes through `FoodLogIntentExtractor.extract(text:)`.
    /// - iOS<26 / macOS<26 OR flag OFF → throws `.unavailable` so the
    ///   caller falls back to its own non-FM path (e.g. VoiceLogSheet's
    ///   single-item ad-hoc entry).
    /// - Underlying FM errors (.notFoodLog, .bounded, .sessionFailed) are
    ///   re-thrown verbatim — caller treats them all as "fall back".
    public static func extract(text: String) async throws -> FMFoodLogIntent {
        guard Preferences.fmFoodIntentExtractEnabled else {
            throw FMFoodLogIntentExtractorError.unavailable
        }
        return try await FoodLogIntentExtractor.extract(text: text)
    }

    /// Extract zero-or-more food candidates as a flat `[Candidate]` list.
    ///
    /// Returns `[primary] + additionalItems` flattened — the shape future
    /// Apple Intents wiring will read. Loses the `mealType` hint by design;
    /// callers that need it should use `extract(text:)` instead.
    public static func extractCandidates(text: String) async throws -> [Candidate] {
        let intent = try await extract(text: text)
        let primary = FMFoodLogIntent.Item(
            foodName: intent.foodName,
            quantity: intent.quantity,
            unit: intent.unit
        )
        return [primary] + intent.additionalItems
    }

    /// Returns the same prompt the underlying FoodLogIntentExtractor uses.
    /// Exposed so tier-0 tests can pin prompt content without reaching into
    /// the FoundationModels-namespaced helper.
    public static func buildPrompt(for text: String) -> String {
        FoodLogIntentExtractor.buildPrompt(for: text)
    }
}
