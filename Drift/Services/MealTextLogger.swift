import Foundation
import DriftCore

/// Parses a free-text / spoken meal description into structured food items using
/// the SAME model that powers Drift Coach (Nebius cloud when provisioned). Feeds
/// the editable `MealReviewSheet` so text + voice logging reuse the Snap review
/// surface. Falls back to nil when the model is unreachable or returns nothing —
/// the caller then degrades to the on-device extractor. #food-logging-reuse
@MainActor
enum MealTextLogger {

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
    static func parse(_ text: String) async -> PhotoLogResponse? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Use the Drift Coach cloud model (same as chat) when a key is
        // provisioned and the toggle is on (off in unit tests → offline path).
        guard AIBackendCoordinator.hasCoachCloud, Preferences.coachCloudFoodParseEnabled else { return nil }
        AIBackendCoordinator.installCoachBackend()

        let raw = await LocalAIService.shared.respondDirect(
            systemPrompt: systemPrompt, message: trimmed)
        return decode(raw)
    }

    /// Extract + decode the first top-level JSON object from the model's reply.
    /// Pure (no I/O) so it's unit-testable. Returns nil when there's no decodable
    /// object or it has no items.
    nonisolated static func decode(_ raw: String) -> PhotoLogResponse? {
        guard let json = extractJSONObject(raw),
              let data = json.data(using: .utf8),
              let resp = try? JSONDecoder().decode(PhotoLogResponse.self, from: data),
              !resp.items.isEmpty else { return nil }
        return resp
    }

    /// First brace-balanced `{...}` substring. Good enough for our JSON (no
    /// braces inside string values), mirroring the chat propose-meal extractor.
    nonisolated static func extractJSONObject(_ s: String) -> String? {
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var idx = start
        while idx < s.endIndex {
            switch s[idx] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(s[start...idx]) }
            default: break
            }
            idx = s.index(after: idx)
        }
        return nil
    }
}
