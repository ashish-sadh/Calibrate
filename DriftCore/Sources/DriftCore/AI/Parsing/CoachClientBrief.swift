import Foundation

/// The coach-facing read of a client: what changed, what to watch, what to ask
/// on Monday. A human coach opening a client should not have to reconstruct the
/// story from a note log and six averages — that reconstruction is exactly what
/// a model is good at.
///
/// Runs on the same Nebius path as Coach Me. Falls back to a deterministic
/// local summary when the cloud is unreachable, so the card is never empty —
/// it just stops reading like a colleague's handover.
@MainActor
public enum CoachClientBrief {

    static let systemPrompt = """
    You are briefing a strength coach on one of their clients before a session. You have the client's intake summary, dated notes, and averages for the last week.

    Return ONLY a JSON object — no prose, no markdown fences:
    {"headline":"string","watch":["string"],"ask":["string"]}

    Rules:
    - "headline" is one sentence, under 25 words: how this client is actually doing right now.
    - "watch" is at most 3 short items the coach should keep an eye on — a pain rating that rose, adherence that slipped, a stalled lift. Empty array if genuinely nothing.
    - "ask" is at most 3 short questions worth asking this client next session. Concrete, not generic — "How's the lower back after Saturday?" not "How are you feeling?".
    - Only use what you were given. Never invent a number, a lift, or an injury. If the data is thin, say so in the headline rather than padding.
    - No medical advice and no diagnosis. If pain is 7 or higher, note it is worth a professional look and leave it there.
    """

    public struct Brief: Sendable, Equatable {
        public var headline: String
        public var watch: [String]
        public var ask: [String]

        public init(headline: String, watch: [String] = [], ask: [String] = []) {
            self.headline = headline
            self.watch = watch
            self.ask = ask
        }
    }

    /// Generate the brief, or nil when the cloud is off/unreachable — the caller
    /// falls back to `offline(for:)`.
    public static func generate(for briefing: ClientBriefing, username: String) async -> Brief? {
        guard CoachCloud.isConfigured, !briefing.isEmpty else { return nil }
        CoachCloud.install()

        var context = ["Client: @\(username)"]
        if !briefing.summary.isEmpty { context.append("Intake: \(briefing.summary)") }
        let metricLines = briefing.metrics.lines.map { "\($0.label): \($0.value)" }
        if !metricLines.isEmpty {
            context.append("Last \(briefing.metrics.windowDays) days — " + metricLines.joined(separator: ", "))
        }
        if !briefing.notes.isEmpty {
            context.append("Notes (newest last):")
            // Recent only: a six-month-old sore shoulder is history, last week's
            // is a training constraint, and the model can't tell them apart if
            // we hand it everything flat.
            context += briefing.notes.suffix(15).map { "- \($0.date): \($0.text)" }
        }

        return await CloudExtractionPolicy.withRetry {
            let raw = await LocalAIService.shared.respondDirect(
                systemPrompt: systemPrompt, message: context.joined(separator: "\n"),
                maxTokens: CloudExtractionPolicy.textMaxTokens,
                temperature: CloudExtractionPolicy.temperature)
            return decode(raw)
        }
    }

    nonisolated public static func decode(_ raw: String) -> Brief? {
        guard let json = CloudExtractionPolicy.extractJSONObject(raw),
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let headline = root["headline"] as? String,
              !headline.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        return Brief(headline: headline,
                     watch: Array(strings(root["watch"]).prefix(3)),
                     ask: Array(strings(root["ask"]).prefix(3)))
    }

    nonisolated static func strings(_ any: Any?) -> [String] {
        guard let raw = any as? [Any] else { return [] }
        return raw.compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Cloud-free fallback. Deliberately states only what the numbers say — no
    /// interpretation, because inventing coaching insight offline would be
    /// worse than admitting there isn't any.
    nonisolated public static func offline(for briefing: ClientBriefing) -> Brief {
        var parts: [String] = []
        if let workouts = briefing.metrics.workoutsCompleted {
            parts.append("\(workouts) workout\(workouts == 1 ? "" : "s") in the last \(briefing.metrics.windowDays) days")
        }
        if let sleep = briefing.metrics.avgSleepHours {
            parts.append(String(format: "averaging %.1fh sleep", sleep))
        }
        if let protein = briefing.metrics.avgProteinG {
            parts.append(String(format: "%.0fg protein/day", protein))
        }
        let headline = parts.isEmpty
            ? "Not enough shared yet to summarise."
            : parts.joined(separator: ", ") + "."

        // A pain rating high enough to change what you program is worth
        // surfacing even without a model.
        var watch: [String] = []
        if let recent = briefing.notes.last { watch.append("Latest note: \(recent.text)") }

        return Brief(headline: headline, watch: watch)
    }
}
