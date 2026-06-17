import Foundation

/// Narrates the deterministic `BriefInput` into 1–3 human `BriefItem`s for the proactive
/// "Today's Brief" coaching surface (epic #875, S2 / #877).
///
/// The genuinely new capability of the arc is LLM *synthesis* across 2–3 deterministic signals
/// (e.g. "protein dipped 3 days and sleep is down — recovery risk"), not a re-skin of the
/// one-rule-one-line cards. Backend-agnostic: it calls whatever backend `LocalAIService` currently
/// routes to (the llama.cpp/Gemma default per #860), so it never collides with the FM-reliability
/// arc.
///
/// Structured as a pure core (`buildPrompt` + `parse` + the `isGrounded` grounding predicate — all
/// `nonisolated`, fully Tier-0 tested on canned model output, NO model call) behind a thin
/// `@MainActor` `narrate` that touches the live backend. The grounding predicate is the safety
/// property of the whole arc: a narrated item may phrase and combine signals but must never state a
/// number the deterministic layer didn't compute — the over-claim / 2-point-extrapolation bug class
/// (#801). The companion live grounding RUN that measures how often the model stays grounded lives
/// in `BriefNarratorGroundingEval` (#885, env-gated Tier-4), OFF this commit path.
///
/// Pure logic, no UIKit/HealthKit import → DriftCore (tenet #6).
public enum BriefNarrator {

    /// Max insights the brief surfaces — matches `CoachingBriefService.signalCap` and
    /// visual_criterion v1 (never a wall of cards).
    public static let maxItems = 3

    /// System prompt for the brief — backend-agnostic, sent verbatim through
    /// `LocalAIService.respondDirect`. The grounding instruction is the prompt-side half of the
    /// safety property; `parse`'s `isGrounded` filter is the deterministic enforcement half.
    public static let systemPrompt = """
    You are Drift's health coach writing a short daily brief. You are given 1-3 SIGNALS the app \
    already computed from the user's own logged data. Synthesize them into 1-3 short, specific insights.

    Hard rules:
    - Use ONLY the facts in the signals. NEVER state a number, date, percentage, or statistic that \
    does not already appear in the signals. Do not compute new numbers.
    - Each insight must reference exactly one signal by its id (the most relevant one).
    - Be goal-aware in tone, but never invent a stance the signal doesn't support.
    - Output ONLY a JSON array — no prose, no markdown fences. Each element is an object:
      {"sourceSignalId": "<an id from the signals>", "title": "<<=8-word headline>", \
    "detail": "<one supportive sentence, no new numbers>", "seedQuery": "<a follow-up question \
    the user could ask you>"}
    """

    // MARK: - Pure core (nonisolated, Tier-0 tested)

    /// The focused user message listing each signal with its stable id, source, and the one fact
    /// the narrator may state. Pure — `narrate` feeds the live response back through `parse`; tests
    /// assert on this string and on `parse` independently of any model call.
    public static func buildPrompt(from input: BriefInput) -> String {
        var lines = ["SIGNALS:"]
        for (i, signal) in input.signals.enumerated() {
            lines.append("[\(i + 1)] id=\(signal.id) (\(signal.source.rawValue))")
            lines.append("    headline: \(signal.title)")
            lines.append("    fact: \(signal.detail)")
        }
        lines.append("")
        lines.append("Write 1-\(maxItems) insights as a JSON array, each referencing one signal id above.")
        return lines.joined(separator: "\n")
    }

    /// Parse a raw model response into 1–`maxItems` grounded `BriefItem`s. Pure and deterministic:
    /// extracts the JSON array, and for each entry — drops it unless its `sourceSignalId` names a
    /// real input signal, drops it unless every numeric claim is grounded in the supplied signals
    /// (`isGrounded`), derives `alignment` 1:1 from that signal's `goalDirection` (NEVER from the
    /// model — the model phrases, the deterministic layer owns the stance), dedups by signal id
    /// (first wins), and caps at `maxItems`. A thin-data or empty input yields no items.
    public static func parse(_ raw: String, input: BriefInput) -> [BriefItem] {
        guard !input.isThinData, !input.signals.isEmpty,
              let jsonArray = extractJSONArray(raw),
              let data = jsonArray.data(using: .utf8),
              let rawItems = try? JSONDecoder().decode([RawBriefItem].self, from: data)
        else { return [] }

        let signalsByID = Dictionary(input.signals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var items: [BriefItem] = []
        var seen = Set<String>()
        for raw in rawItems {
            let title = raw.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = raw.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let seedQuery = raw.seedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !detail.isEmpty,
                  let signal = signalsByID[raw.sourceSignalId],
                  seen.insert(signal.id).inserted,
                  isGrounded(title: title, detail: detail, in: input)
            else { continue }

            items.append(BriefItem(
                title: title,
                detail: detail,
                seedQuery: seedQuery.isEmpty ? "Tell me more about \(signal.title.lowercased())" : seedQuery,
                sourceSignalId: signal.id,
                alignment: alignment(for: signal.goalDirection)
            ))
            if items.count == maxItems { break }
        }
        return items
    }

    /// The grounding predicate (the over-claim bug-class guard): every numeric token a narrated
    /// item states must already appear — as a whole token, not a substring, so "5" never passes off
    /// "15" — somewhere in the supplied `BriefInput` signals. The narrator may freely re-word and
    /// combine the signals' prose; it may NOT introduce a number nobody computed.
    ///
    /// Scope: this guards DIGIT-form numbers (the over-claim / 2-point-extrapolation class produces
    /// computed digits like "2.3 kg" or "53%"). A spelled-out hallucination ("forty-two pounds")
    /// would slip past; the prompt's "never state a number" instruction is the first-line guard for
    /// that, and #885's live eval measures how often the model obeys it. It also guards number
    /// INTRODUCTION, not semantics — a number that IS in a signal but is used in a false claim is
    /// grounded here, so callers must not treat grounding as a full factual-truth gate.
    public static func isGrounded(title: String, detail: String, in input: BriefInput) -> Bool {
        let claimed = numericTokens(in: title + " " + detail)
        guard !claimed.isEmpty else { return true }
        let supplied = input.signals.reduce(into: Set<String>()) { acc, s in
            acc.formUnion(numericTokens(in: s.title + " " + s.detail))
        }
        return claimed.isSubset(of: supplied)
    }

    /// Whole numeric tokens (integers and decimals) in `text`. Set membership — not substring
    /// containment — is what makes the grounding check reject "5" against a source that only has
    /// "15".
    static func numericTokens(in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var tokens = Set<String>()
        for match in regex.matches(in: text, range: range) {
            if let r = Range(match.range, in: text) { tokens.insert(String(text[r])) }
        }
        return tokens
    }

    /// Map a signal's goal direction to the item's goal-aware alignment 1:1. Deterministic so the
    /// color is owned by the computed signal, never by free model text.
    static func alignment(for direction: BriefSignal.GoalDirection) -> BriefItem.GoalAlignment {
        switch direction {
        case .aligned: return .aligned
        case .against: return .against
        case .neutral: return .neutral
        }
    }

    /// Eval seam (#885): of the model's id-valid candidate items, how many are grounded. Measured
    /// BEFORE `parse`'s grounding filter drops the ungrounded ones, so the rate reflects raw model
    /// behavior rather than the always-clean post-filter output. Prod's safety filter and this
    /// metric share the one `isGrounded` predicate. `total == 0` means the model emitted no usable
    /// JSON — the eval treats that as a hard miss, not a vacuous pass.
    public static func groundingReport(raw: String, input: BriefInput) -> (grounded: Int, total: Int) {
        guard let jsonArray = extractJSONArray(raw),
              let data = jsonArray.data(using: .utf8),
              let rawItems = try? JSONDecoder().decode([RawBriefItem].self, from: data)
        else { return (0, 0) }
        let validIDs = Set(input.signals.map(\.id))
        let valid = rawItems.filter { validIDs.contains($0.sourceSignalId) }
        let grounded = valid.filter { isGrounded(title: $0.title, detail: $0.detail, in: input) }.count
        return (grounded, valid.count)
    }

    /// Slice out the outermost JSON array from a possibly-chatty / fenced model response.
    static func extractJSONArray(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"),
              start < end else { return nil }
        return String(text[start...end])
    }

    /// The narrator's wire shape — `alignment` is intentionally absent (the model never sets it;
    /// `parse` derives it from the source signal).
    struct RawBriefItem: Decodable {
        let sourceSignalId: String
        let title: String
        let detail: String
        let seedQuery: String
    }

    // MARK: - Impure boundary (@MainActor)

    /// Narrate the live brief by calling the active backend and parsing its response. The only
    /// impure seam — kept thin; all prompt-building, parsing, and grounding lives in the pure core
    /// above. Thin-data / no-signal inputs short-circuit without a model call.
    @MainActor
    public static func narrate(_ input: BriefInput) async -> [BriefItem] {
        guard !input.isThinData, !input.signals.isEmpty else { return [] }
        let raw = await LocalAIService.shared.respondDirect(
            systemPrompt: systemPrompt,
            message: buildPrompt(from: input)
        )
        return parse(raw, input: input)
    }
}
