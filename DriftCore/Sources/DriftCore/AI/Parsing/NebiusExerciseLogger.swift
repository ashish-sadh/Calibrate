import Foundation

/// Parses a free-text / spoken WORKOUT description into structured exercise
/// entries using the SAME cloud model that powers Drift Coach (Nebius when
/// provisioned). This is workout logging's cloud-first path: the on-device
/// Apple Foundation Model pattern-completes a single utterance into a whole
/// stereotypical workout ("3 sets of back extensions" → squat/deadlift/curl/…),
/// which is a trust-breaking data-integrity bug (#969). The bigger cloud brain
/// extracts only what was said; on-device FM stays as the OFFLINE fallback.
///
/// Mirrors `MealTextLogger` (the food-side equivalent). Returns nil on any
/// failure / empty result so the caller falls back to `FoundationModelsExerciseExtractor`.
///
/// In DriftCore (not the iOS app) so Android logs exercises through the same
/// cloud brain with the same prompt — the local regex parser is the offline
/// fallback on both platforms, never Android's default (#1064).
@MainActor
public enum NebiusExerciseLogger {

    /// Instruct the model to return ONLY the entries JSON — same numeric shape as
    /// `FMExerciseTranscriptSchema` so downstream mapping + bounds are identical.
    static let systemPrompt = """
    You convert a workout description into structured exercise data.
    Return ONLY a JSON object — no prose, no markdown fences — in exactly this shape:
    {"entries":[{"exerciseName":"string","sets":number|null,"reps":number|null,"weight":number|null,"durationMinutes":number|null,"category":"strength|cardio|mobility|sports"}]}

    CRITICAL — do not hallucinate: extract ONLY exercises the user explicitly named. Never invent, infer, or pad the list with movements that were not literally stated. Most messages name just one or two exercises. If the user names exactly one exercise, return exactly one entry. "3 sets of back extensions of 10 reps each" is ONE exercise (exerciseName="back extension", sets=3, reps=10), NOT a full workout.

    Rules:
    - "3x10" = 3 sets of 10 reps. "@135" = 135 lbs. "at 60 kg" → convert kg×2.205 to lbs, round to nearest pound.
    - Weights ALWAYS in pounds. Bodyweight movements → weight null. Cardio → sets/reps/weight null, set durationMinutes.
    - Categories: strength (lifts/calisthenics with sets+reps), cardio (running/cycling/rowing/swim), mobility (yoga, surya namaskar, stretching), sports (soccer, basketball, climbing).
    - Use canonical names ("bench press" not "bench", "surya namaskar" for sūryanamaskār, "running" not "ran").
    - Indian / Hinglish terms welcome ("ek set mein 10 reps" = one set of 10; "sūryanamaskār 12 sets" → mobility, sets=12; "deadlift 5x5 80kg" → weight=176).
    - Return {"entries":[]} when the message is not a workout (e.g. "show my weight", "what did I eat").
    """

    /// Parse `text` via the coach cloud model. nil when the cloud isn't
    /// configured, is unreachable, or returns nothing valid — the caller then
    /// falls back to the on-device FM extractor.
    public static func parse(_ text: String) async -> [FMExerciseEntry]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard CoachCloud.isConfigured else { return nil }
        CoachCloud.install()

        // Extraction budgets + one transient retry (CloudExtractionPolicy):
        // chat's 512 tokens truncates a long workout, default temperature
        // parses the same text into different numbers run-to-run.
        return await CloudExtractionPolicy.withRetry {
            let raw = await LocalAIService.shared.respondDirect(
                systemPrompt: systemPrompt, message: trimmed,
                maxTokens: CloudExtractionPolicy.textMaxTokens,
                temperature: CloudExtractionPolicy.temperature)
            return decode(raw)
        }
    }

    /// Extract + decode the first top-level JSON object, validate each entry
    /// against `ExerciseTranscriptBounds`, and drop unnamed / out-of-range
    /// entries. Pure (no I/O) so it's unit-testable. nil when nothing decodable
    /// or nothing survives validation.
    nonisolated static func decode(_ raw: String) -> [FMExerciseEntry]? {
        guard let json = extractJSONObject(raw),
              let data = json.data(using: .utf8),
              let resp = try? JSONDecoder().decode(Response.self, from: data) else { return nil }

        let mapped: [FMExerciseEntry] = resp.entries.compactMap { e in
            let name = e.exerciseName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let category = FMExerciseEntry.Category(rawValue: e.category.lowercased()) ?? .strength
            let entry = FMExerciseEntry(
                exerciseName: name, sets: e.sets, reps: e.reps, weight: e.weight,
                unit: .lbs, durationMinutes: e.durationMinutes, category: category)
            // Drop anything the on-device bounds would also reject — same safety
            // valve the FM path enforces, so a cloud glitch can't inject junk.
            return ExerciseTranscriptBounds.violation(in: entry) == nil ? entry : nil
        }
        guard !mapped.isEmpty else { return nil }
        // Cap at the same ceiling as the FM path (guards a runaway response).
        return Array(mapped.prefix(ExerciseTranscriptBounds.maxEntries))
    }

    /// First brace-balanced `{...}` substring (JSON has no braces inside string
    /// values here), mirroring `MealTextLogger.extractJSONObject`.
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

    private struct Response: Codable {
        let entries: [Entry]
        struct Entry: Codable {
            let exerciseName: String
            let sets: Int?
            let reps: Int?
            let weight: Double?
            let durationMinutes: Int?
            let category: String
        }
    }
}
