import Foundation

/// Parses a free-text / spoken meal description into structured food items
/// using the SAME cloud model that powers Drift Coach (Nebius when
/// provisioned). Feeds the editable review surface so text + voice logging
/// reuse the Snap review shape (`PhotoLogResponse`). Returns nil when the
/// model is unreachable or returns nothing — the caller then degrades to the
/// offline parser (`AIActionExecutor.parseMultiItemMeal`). #food-logging-reuse
///
/// In DriftCore (moved from the iOS app's `MealTextLogger`, #1101) so
/// Android's Describe flow logs meals through the same cloud brain with the
/// same prompt — mirroring `NebiusExerciseLogger`, the workout-side twin.
@MainActor
public enum NebiusMealLogger {

    /// Instruct the model to return ONLY the PhotoLogResponse JSON shape (same
    /// keys the photo path decodes) so we can `Codable`-decode the reply.
    static let systemPrompt = """
    You convert a meal description into structured nutrition data.
    Return ONLY a JSON object — no prose, no markdown fences — in exactly this shape:
    {"items":[{"name":"string","grams":number,"calories":number,"protein_g":number,"carbs_g":number,"fat_g":number,"fiber_g":number,"serving_unit":"g|piece|slice|cup|bowl|tbsp|plate","serving_amount":number,"confidence":"high|medium|low"}],"overall_confidence":"high|medium|low","notes":null}
    Rules:
    - One entry per distinct food. If a quantity is stated ("2 rotis", "a bowl of dal"), reflect it in grams + serving_amount.
    - Estimate macros for the described portion. Indian food is the default cuisine — assume typical home-cooked portions.
    - Never invent foods that weren't mentioned. If the text names no food, return {"items":[],"overall_confidence":"low","notes":null}.
    """

    /// Parse `text` via the coach cloud model. Returns nil on any failure or an
    /// empty result so the caller can fall back.
    public static func parse(_ text: String) async -> PhotoLogResponse? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Cloud only when a key is provisioned and the toggle is on (off in
        // unit tests → offline path).
        guard CoachCloud.isConfigured, Preferences.coachCloudFoodParseEnabled else { return nil }
        CoachCloud.install()

        // Extraction budgets + one transient retry (CloudExtractionPolicy):
        // chat's 512 tokens truncates a many-item meal (a 12-item thali is the
        // notebook-page bug in food form), default temperature estimates
        // different macros for the same text run-to-run.
        return await CloudExtractionPolicy.withRetry {
            let raw = await LocalAIService.shared.respondDirect(
                systemPrompt: systemPrompt, message: trimmed,
                maxTokens: CloudExtractionPolicy.textMaxTokens,
                temperature: CloudExtractionPolicy.temperature)
            return decode(raw)
        }
    }

    /// Extract + decode the first top-level JSON object from the model's reply.
    /// Pure (no I/O) so it's unit-testable. Returns nil when there's no
    /// decodable object or it has no items.
    nonisolated public static func decode(_ raw: String) -> PhotoLogResponse? {
        guard let json = CloudExtractionPolicy.extractJSONObject(raw),
              let data = json.data(using: .utf8),
              let resp = try? JSONDecoder().decode(PhotoLogResponse.self, from: data),
              !resp.items.isEmpty else { return nil }
        return resp
    }
}
