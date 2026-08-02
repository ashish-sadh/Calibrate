import Foundation

/// WHEN to teach anatomy, and when to shut up about it.
///
/// The operator's constraint is the whole design (2026-08-02): *"Don't force
/// education but know when you bring and tell them these are true muscles and
/// that's why we are picking some exercises."* So this type is deliberately
/// conservative — it returns nil far more often than it returns a lesson.
///
/// `MuscleGuide` knows things. This decides whether saying one of them is
/// welcome. Splitting them is what keeps the coach from turning into a textbook:
/// a lesson surfaces on a moment the user themselves opened (they named a
/// muscle, or said something hurts, or just got handed a session), never on a
/// timer and never twice for the same muscle.
public enum MuscleEducation {

    /// Why this lesson is being shown. Drives the wording — a muscle that hurts
    /// is not introduced the same way as one you're about to train.
    public enum Reason: String, Sendable, Equatable {
        /// They said something hurts there. The most important one to get right.
        case injury
        /// They named it as what they want to train.
        case focus
        /// It's the lead muscle of the session just drafted.
        case session
    }

    /// One teachable moment: what to say, and what to light up on the figure.
    public struct Lesson: Sendable, Equatable, Identifiable {
        /// The Drift catalog muscle key ("lats", "shoulders").
        public let muscle: String
        public let info: MuscleInfo
        public let reason: Reason
        /// Library slugs to highlight on the body diagram.
        public let slugs: [String]
        /// Which view shows it best.
        public let side: BodyDiagram.Side

        public var id: String { muscle }

        /// The one line above the diagram. Reason-specific on purpose.
        public var headline: String {
            switch reason {
            case .injury:
                return "Your \(info.displayName.lowercased()) — \(info.function.lowercased())"
            case .focus:
                return "\(info.displayName) — \(info.function.lowercased())"
            case .session:
                return "Today leads with your \(info.displayName.lowercased())"
            }
        }

        /// The explanatory body. Everyday framing first, because that's the part
        /// that actually teaches; the anatomy name trails it for the person who
        /// wants it.
        public var detail: String {
            var parts: [String] = []
            if let everyday = info.everyday { parts.append(everyday + ".") }
            if !info.heads.isEmpty {
                let heads = info.heads.map { "\($0.name) — \($0.role)" }.joined(separator: "; ")
                parts.append("It's really \(info.heads.count) parts: \(heads).")
            }
            switch reason {
            case .injury:
                parts.append("We'll train around it rather than through it.")
            case .focus, .session:
                if !info.trainedBy.isEmpty {
                    parts.append("That's why the picks are \(info.trainedBy.prefix(3).joined(separator: ", ")).")
                }
            }
            return parts.joined(separator: " ")
        }
    }

    // MARK: - Recognising a muscle in free text

    /// Coarse words people actually use, mapped to the catalog muscle they most
    /// likely mean. Checked AFTER exact names, so "lats" beats "back".
    ///
    /// Deliberately incomplete: a word that could mean three things ("core",
    /// "arms") resolves to the one a coach would ask about first, and anything
    /// genuinely ambiguous is left out entirely rather than guessed.
    private static let colloquial: [(word: String, muscle: String)] = [
        ("lower back", "lower back"), ("upper back", "middle back"),
        ("mid back", "middle back"), ("lat", "lats"),
        ("shoulder", "shoulders"), ("delt", "shoulders"), ("rotator cuff", "shoulders"),
        ("pec", "chest"), ("chest", "chest"),
        ("bicep", "biceps"), ("tricep", "triceps"), ("forearm", "forearms"),
        ("quad", "quadriceps"), ("thigh", "quadriceps"),
        ("hamstring", "hamstrings"), ("ham", "hamstrings"),
        ("glute", "glutes"), ("butt", "glutes"), ("hip", "glutes"),
        ("calf", "calves"), ("calves", "calves"),
        ("ab", "abdominals"), ("core", "transverse abdominis"),
        ("oblique", "obliques"), ("trap", "traps"), ("neck", "neck"),
        ("knee", "quadriceps"), ("elbow", "triceps"),
        // "back" last: it's the vaguest word in the gym, and lats is the
        // muscle someone means often enough to be worth showing.
        ("back", "lats"),
    ]

    /// Find the muscle someone named, if they named one.
    ///
    /// Exact catalog names and nicknames win over colloquial words, so "my lats
    /// are sore" resolves to lats rather than falling through to the generic
    /// "back". Returns nil when nothing is named — the common case.
    public static func muscleNamed(in text: String) -> String? {
        let t = " " + text.lowercased() + " "

        // Exact catalog entries first, longest name first so "lower back" is
        // tried before "back".
        for key in MuscleInfo.allCovered.sorted(by: { $0.count > $1.count }) {
            guard let info = MuscleInfo.info(for: key) else { continue }
            for name in [key, info.displayName.lowercased(), info.nickname?.lowercased()].compactMap({ $0 })
            where !name.isEmpty {
                if t.contains(" \(name) ") || t.contains(" \(name)s ") || t.contains(" \(name),") {
                    return key
                }
            }
        }

        for (word, muscle) in colloquial where t.contains(word) {
            return muscle
        }
        return nil
    }

    // MARK: - Deciding whether to teach

    /// Words that mean "this hurts". An injury lesson is the one moment where
    /// explaining the muscle is nearly always welcome — the person is already
    /// thinking about that body part.
    private static let painWords = ["hurt", "hurts", "pain", "painful", "sore", "sore.",
                                    "ache", "aching", "achy", "tight", "tightness",
                                    "injury", "injured", "strain", "strained", "tweak",
                                    "tweaked", "niggle", "impinge", "impingement"]

    /// A lesson for something the user just said, or nil.
    ///
    /// Two openings only:
    /// - they described PAIN in a body part → explain that muscle, and say we'll
    ///   work around it;
    /// - they named a muscle as what they want to train → explain what it does.
    ///
    /// `alreadyTaught` is the anti-lecture guard: one muscle is explained once
    /// per conversation, however many times it comes up.
    public static func lesson(forUserText text: String,
                             alreadyTaught: Set<String> = []) -> Lesson? {
        guard let muscle = muscleNamed(in: text) else { return nil }
        guard !alreadyTaught.contains(muscle) else { return nil }

        let lower = text.lowercased()
        let hurts = painWords.contains { lower.contains($0) }
        // A muscle named with no pain and no training intent is just chat —
        // "my back was in the car all day" doesn't want an anatomy lesson.
        let wantsToTrain = ["train", "work", "hit", "build", "grow", "focus",
                            "target", "want"].contains { lower.contains($0) }
        guard hurts || wantsToTrain else { return nil }

        return make(muscle, reason: hurts ? .injury : .focus)
    }

    /// A lesson for a session just drafted, or nil.
    ///
    /// Explains the LEAD muscle — the one the session is mostly about — so the
    /// card answers "why these exercises" without being asked. One per session,
    /// and never one already taught.
    public static func lesson(forSession template: WorkoutTemplate,
                             alreadyTaught: Set<String> = []) -> Lesson? {
        let covered = CoachProgramBuilder.muscleCoverage(of: template)
        for name in covered {
            let key = name.lowercased()
            guard !alreadyTaught.contains(key), MuscleInfo.info(for: key) != nil else { continue }
            return make(key, reason: .session)
        }
        return nil
    }

    private static func make(_ muscle: String, reason: Reason) -> Lesson? {
        guard let info = MuscleInfo.info(for: muscle) else { return nil }
        let slugs = BodyDiagram.librarySlugs(forDriftMuscle: muscle)
        // A muscle with no drawable region would render an empty figure — worse
        // than no card at all.
        guard !slugs.isEmpty else { return nil }
        return Lesson(muscle: muscle, info: info, reason: reason, slugs: slugs,
                      side: BodyDiagram.preferredSide(forDriftMuscle: muscle))
    }
}
