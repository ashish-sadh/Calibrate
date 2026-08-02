import Foundation

/// What a real coach asks before writing anyone a program.
///
/// Modelled directly on an actual intake conversation (operator ↔ client,
/// 2026-07-28) rather than invented: the slot list and its ORDER are what a
/// human coach actually reached for over WhatsApp — days first, then goal, then
/// what's in the gym, then what the person can already do, and only then the
/// awkward questions about pain. Getting the order right matters: asking about
/// injuries before you know whether they own a barbell reads like a medical
/// form, not a conversation.
///
/// The old `buildSmartSession` path skipped all of this and jumped straight to
/// a generated session, which is why "Coach Me" felt like a dice roll.
public struct CoachIntake: Codable, Sendable, Equatable {

    // MARK: - Slots (the answers a coach needs)

    /// "2 day workout ... on Saturday and Sunday"
    public var daysPerWeek: Int?
    /// Named days when the user volunteers them — a coach who knows you train
    /// Sat/Sun writes a different split than one who knows only "twice".
    public var trainingDays: [String] = []
    /// "Goal is just being fit and mobile" — free text, deliberately. Forcing
    /// this into hypertrophy/strength/endurance loses the actual answer.
    public var goal: String?
    /// "Each workout is 45 mins"
    public var sessionMinutes: Int?
    /// "Everything is there, fully stocked gym" / "resistance bands at home"
    public var equipment: String?
    /// "Comfortable with all major compound exercises" — barbell vs machines.
    public var usesBarbell: Bool?
    /// "Squats / bench press / pull ups / pushups". Seeds the program with lifts
    /// the person already trusts, which is most of why a program gets followed.
    public var familiarExercises: [String] = []
    /// "Back a little bit"
    public var problemAreas: [String] = []
    /// "Rate your discomfort/pain out of 10" → "2-3". Stored as the worst of a
    /// range so the program errs conservative.
    public var painLevel: Int?
    /// "I want to specifically add mobility exercises"
    public var requests: [String] = []

    public init() {}

    // MARK: - Where are we in the conversation?

    /// The next thing to ask. Nil when there's enough to write a program —
    /// this is what lets Coach Me resume mid-conversation instead of starting
    /// over, and what stops it interrogating someone who already answered.
    public var nextStep: Step? {
        Step.ordered.first { !isFilled($0) }
    }

    public func isFilled(_ step: Step) -> Bool {
        switch step {
        case .schedule:   return daysPerWeek != nil
        case .goal:       return goal?.isEmpty == false
        case .duration:   return sessionMinutes != nil
        case .equipment:  return equipment?.isEmpty == false
        case .style:      return usesBarbell != nil
        case .familiar:   return !familiarExercises.isEmpty
        case .injuries:   return !problemAreas.isEmpty || painLevel != nil || askedInjuries
        case .pain:       return painLevel != nil || problemAreas.isEmpty
        case .requests:   return askedRequests
        }
    }

    /// "No injuries" and "not asked yet" are different states, and a program
    /// written without knowing which one you're in is guessing. Same for
    /// requests — silence is not the same as "nothing to add".
    public var askedInjuries = false
    public var askedRequests = false

    /// Enough to write something useful. Deliberately lower than "every slot
    /// filled": a coach who has days, duration and equipment can draft, then
    /// refine. Waiting for perfect information is how intake becomes a form.
    /// The one non-negotiable: injuries must have been ASKED about (operator
    /// 2026-07-29: "the coach should have asked about injury") — no real coach
    /// programs without asking what hurts; "nothing hurts" satisfies it.
    public var canDraft: Bool {
        daysPerWeek != nil && sessionMinutes != nil && equipment?.isEmpty == false
            && isFilled(.injuries)
    }

    /// Enough to write ONE session for right now.
    ///
    /// Deliberately far lower than `canDraft`: someone standing in the gym
    /// asking what to do today does not have a weekly schedule to give you, and
    /// asking for one is the interrogation the operator reported (2026-08-02) —
    /// "I just want one exercise" answered with "how many days a week can you
    /// train?". Knowing how long they have is enough to fill the time sensibly;
    /// equipment and focus refine it but shouldn't block it, and both default
    /// safely (full gym, whatever's rested).
    public var canDraftToday: Bool { sessionMinutes != nil }

    // MARK: - Steps

    public enum Step: String, Codable, Sendable, CaseIterable {
        case schedule, goal, duration, equipment, style, familiar, injuries, pain, requests

        /// Ask order, taken from the real conversation.
        public static var ordered: [Step] {
            [.schedule, .goal, .duration, .equipment, .style, .familiar, .injuries, .pain, .requests]
        }

        /// The coach's actual phrasing where it was good. Short, one idea per
        /// message — a paragraph of questions gets one answer.
        public var question: String {
            switch self {
            case .schedule:  "How many days a week can you train — and which days?"
            case .goal:      "What are you working towards?"
            case .duration:  "Roughly how long per session?"
            case .equipment: "What have you got to train with — full gym, home setup, anything at home too?"
            case .style:     "Do you use barbell work? Or would you rather stick to machines?"
            case .familiar:  "Send a few exercises you've been doing — just to get a sense, no need to be exhaustive."
            case .injuries:  "Any injury-prone muscles or body parts?"
            case .pain:      "Rate that discomfort out of 10."
            case .requests:  "Anything you specifically want in there?"
            }
        }

        /// Tappable answers. Never the only path — every step accepts free text,
        /// because "fit and mobile" is a better answer than any chip.
        public var suggestions: [String] {
            switch self {
            case .schedule:  ["2 days", "3 days", "4 days", "5 days"]
            case .goal:      ["Get fit and mobile", "Build muscle", "Get stronger", "Lose fat"]
            case .duration:  ["30 min", "45 min", "60 min"]
            case .equipment: ["Full gym", "Home — dumbbells", "Home — bands only", "Bodyweight"]
            case .style:     ["Barbell is fine", "Machines only"]
            case .familiar:  ["Squats, bench, pull-ups", "Not sure — you pick"]
            case .injuries:  ["Nothing", "Back", "Knees", "Shoulders"]
            case .pain:      ["1-2", "2-3", "4-5", "6+"]
            case .requests:  ["Add mobility work", "Nothing else"]
            }
        }
    }

    // MARK: - Summary

    /// One-paragraph recap. Read back before drafting ("here's what I've got")
    /// so a wrong answer gets corrected before it becomes a program, and stored
    /// as the header of `CoachNotes` so a human coach inherits the context
    /// instead of re-interviewing.
    public var summary: String {
        var parts: [String] = []
        if let days = daysPerWeek {
            let named = trainingDays.isEmpty ? "" : " (\(trainingDays.joined(separator: ", ")))"
            parts.append("\(days) days/week\(named)")
        }
        if let minutes = sessionMinutes { parts.append("\(minutes) min sessions") }
        if let goal { parts.append("goal: \(goal)") }
        if let equipment { parts.append(equipment) }
        if let usesBarbell { parts.append(usesBarbell ? "barbell OK" : "machines only") }
        if !familiarExercises.isEmpty {
            parts.append("does: \(familiarExercises.joined(separator: ", "))")
        }
        if !problemAreas.isEmpty {
            let pain = painLevel.map { " (\($0)/10)" } ?? ""
            parts.append("watch: \(problemAreas.joined(separator: ", "))\(pain)")
        }
        if !requests.isEmpty { parts.append("wants: \(requests.joined(separator: ", "))") }
        return parts.isEmpty ? "No intake yet." : parts.joined(separator: " · ")
    }
}
