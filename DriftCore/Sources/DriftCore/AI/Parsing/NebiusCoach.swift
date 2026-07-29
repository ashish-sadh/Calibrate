import Foundation

/// The conversational half of Coach Me. Runs one turn of intake through the
/// same cloud brain as Drift Coach (Nebius), and — crucially — returns BOTH the
/// reply to show AND the slots it understood, so the conversation advances
/// without a second parsing pass.
///
/// Mirrors `NebiusMealLogger` (structured extraction, brace-balanced decode,
/// `CloudExtractionPolicy` budgets). Lives in DriftCore so iOS and Android get
/// one coach with one prompt.
///
/// **Offline ladder.** When the cloud is unreachable the caller falls back to
/// `CoachIntake.Step.question` — the scripted intake. That degrades from "a
/// coach who listens" to "a form that asks in the right order", which is still
/// the whole feature working, just less warmly.
@MainActor
public enum NebiusCoach {

    /// One turn's result.
    public struct Turn: Sendable, Equatable {
        /// What to show the user. One idea per message — the real coach asked
        /// "Deadlifts too?" not a paragraph, and short questions get answers.
        public var reply: String
        /// Slots the model understood from this turn, merged by the caller.
        public var learned: CoachIntake
        /// Something worth remembering that isn't a slot ("travelling next
        /// week", "back's been sore again") — becomes a `CoachNotes` moment.
        public var note: String?
        /// The model believes it has enough to draft.
        public var readyToDraft: Bool
        /// What the user is actually asking for — one session now, or a weekly
        /// program. Nil while it's still ambiguous. Without this the coach
        /// answered "what should I do today?" with a filing cabinet.
        public var ask: CoachProgramBuilder.Ask?
        /// A focus they named for today's session ("legs", "push", "upper").
        public var focus: String?
    }

    static let systemPrompt = """
    You are a strength coach texting a client. You sound like a person who has coached for fifteen years, not a form and not a chatbot.

    Return ONLY a JSON object — no prose, no markdown fences — in exactly this shape:
    {"reply":"string","ask":"today"|"program"|null,"focus":"string|null","slots":{"days_per_week":number|null,"training_days":["string"],"goal":"string|null","session_minutes":number|null,"equipment":"string|null","uses_barbell":boolean|null,"familiar_exercises":["string"],"problem_areas":["string"],"pain_level":number|null,"requests":["string"]},"note":"string|null","ready_to_draft":boolean}

    WHAT THEY WANT — read this before anything else:
    - "what should I do today", "I'm at the gym", "give me a workout", "I have 40 minutes" → ask="today". They want ONE session right now. Do NOT interview them about their weekly schedule; you need only session length, equipment and anything that hurts. Set focus if they named one ("legs", "push", "upper").
    - "make me a plan", "I want to train 3 days a week", "build me a program" → ask="program". A weekly split is what they're after.
    - If it is genuinely unclear, ask which they want — once, in one short line.

    HOW TO TALK:
    - ONE question per reply, under 20 words. Never stack questions. Never number them.
    - React to what they said before you ask the next thing. "Nice, 3 days is plenty." then the question. A question with no reaction reads like a form.
    - Reference what you already know instead of re-asking it. If they told you their back hurts, ask how it's feeling today — don't ask if anything hurts.
    - Never ask something you can infer. "I'm at the gym after work" already tells you they have equipment and it's today.
    - Match their energy. Short answers get short replies. Do not be relentlessly upbeat.
    - Indian gyms and Hinglish are normal ("haa" = yes, "thik hai" = fine).

    INJURY — the part that matters most:
    - If they mention pain or an injury, deal with it BEFORE anything else. Ask where and how bad out of 10.
    - Then say concretely what you'll change: "I'll keep you off deadlifts and swap in a Romanian at light weight." Naming the substitution is the coaching; "we'll be careful" is not.
    - Pain 7+: say plainly it's worth getting looked at, keep the session gentle, and do not program through it. Never diagnose and never name a condition.
    - An old injury that doesn't hurt now still gets trained — avoidance is how weak links persist.

    SLOTS:
    - Only fill a slot they actually answered. Never infer or invent. Omit or null anything unstated. "2-3" for pain takes the HIGHER number.
    - "familiar_exercises" are lifts they say they already do. Keep their wording.
    - "note" is for what's worth remembering but isn't a slot: travel, sleep, stress, a sore day, what motivates them. Null when there's nothing.
    - ready_to_draft: for ask="today", true as soon as you know roughly how long they have. For ask="program", true once you know days/week, session length and equipment. Do not keep interviewing for its own sake — you can refine after they see something.
    """

    /// Run a turn. `history` is prior messages oldest-first as "user: …" /
    /// "coach: …" lines; `known` and `briefing` let the coach skip what it has
    /// already been told, which is the whole point of the memory.
    public static func turn(history: [String], known: CoachIntake, briefing: String) async -> Turn? {
        guard CoachCloud.isConfigured else { return nil }
        CoachCloud.install()

        let context = """
        What I already know: \(known.summary)

        Notes from earlier sessions:
        \(briefing)

        Conversation so far:
        \(history.suffix(20).joined(separator: "\n"))
        """

        return await CloudExtractionPolicy.withRetry {
            let raw = await LocalAIService.shared.respondDirect(
                systemPrompt: systemPrompt, message: context,
                maxTokens: CloudExtractionPolicy.textMaxTokens,
                temperature: CloudExtractionPolicy.temperature)
            return decode(raw)
        }
    }

    /// Pure decode — the cloud CALL is Tier-3, this mapping is Tier-0.
    nonisolated public static func decode(_ raw: String) -> Turn? {
        guard let json = CloudExtractionPolicy.extractJSONObject(raw),
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reply = root["reply"] as? String, !reply.isEmpty else { return nil }

        var learned = CoachIntake()
        if let slots = root["slots"] as? [String: Any] {
            learned.daysPerWeek = intValue(slots["days_per_week"])
            learned.trainingDays = stringArray(slots["training_days"])
            learned.goal = nonEmpty(slots["goal"])
            learned.sessionMinutes = intValue(slots["session_minutes"])
            learned.equipment = nonEmpty(slots["equipment"])
            learned.usesBarbell = slots["uses_barbell"] as? Bool
            learned.familiarExercises = stringArray(slots["familiar_exercises"])
            learned.problemAreas = stringArray(slots["problem_areas"])
            // Clamp: a model returning 12/10 shouldn't drive exercise selection.
            learned.painLevel = intValue(slots["pain_level"]).map { min(max($0, 0), 10) }
            learned.requests = stringArray(slots["requests"])
        }

        let ask: CoachProgramBuilder.Ask?
        switch nonEmpty(root["ask"])?.lowercased() {
        case "today":   ask = .today
        case "program": ask = .program
        default:        ask = nil
        }

        return Turn(reply: reply,
                    learned: learned,
                    note: nonEmpty(root["note"]),
                    readyToDraft: (root["ready_to_draft"] as? Bool) ?? false,
                    ask: ask,
                    focus: nonEmpty(root["focus"]))
    }

    // MARK: - Lenient readers
    //
    // The model returns numbers as Int, Double or String depending on the day;
    // a strict decode would drop a perfectly good answer.

    nonisolated static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    nonisolated static func stringArray(_ any: Any?) -> [String] {
        guard let raw = any as? [Any] else { return [] }
        return raw.compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    nonisolated static func nonEmpty(_ any: Any?) -> String? {
        guard let s = any as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.lowercased() == "null" ? nil : trimmed
    }
}

// MARK: - Merging

public extension CoachIntake {
    /// Fold one turn's understanding into what we already know. Existing
    /// answers WIN — a later turn that says nothing about days must not erase
    /// the day count, and the model omitting a slot means "not mentioned", not
    /// "cleared". Lists union rather than replace, so naming one more exercise
    /// adds to the list instead of narrowing it.
    mutating func merge(_ learned: CoachIntake) {
        if daysPerWeek == nil { daysPerWeek = learned.daysPerWeek }
        if sessionMinutes == nil { sessionMinutes = learned.sessionMinutes }
        if goal == nil { goal = learned.goal }
        if equipment == nil { equipment = learned.equipment }
        if usesBarbell == nil { usesBarbell = learned.usesBarbell }
        // Pain is the exception: a NEW rating replaces the old one, because
        // "it's a 5 now" is the point of asking again.
        if let pain = learned.painLevel { painLevel = pain }

        trainingDays = union(trainingDays, learned.trainingDays)
        familiarExercises = union(familiarExercises, learned.familiarExercises)
        requests = union(requests, learned.requests)
        if !learned.problemAreas.isEmpty {
            problemAreas = union(problemAreas, learned.problemAreas)
            askedInjuries = true
        }
    }

    private func union(_ existing: [String], _ incoming: [String]) -> [String] {
        var seen = Set(existing.map { $0.lowercased() })
        var out = existing
        for item in incoming where seen.insert(item.lowercased()).inserted {
            out.append(item)
        }
        return out
    }
}
