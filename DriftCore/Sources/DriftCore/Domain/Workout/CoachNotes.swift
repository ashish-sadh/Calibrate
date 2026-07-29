import Foundation

/// The coach's memory. Everything Coach Me learns about you — the intake
/// answers, plus the small things you mention in passing ("back's been sore
/// again", "travelling next week") — kept locally so the next conversation
/// starts where the last one ended rather than from zero.
///
/// Two audiences, deliberately:
/// 1. **Coach Me itself** — the notes ride along as context, so it stops
///    re-asking what it already knows.
/// 2. **A human coach** — when you connect one (the sharing feature), they
///    inherit a written history instead of re-running the intake over
///    WhatsApp. That is the operator's "worth storing these AI notes with AI
///    coach to help give more info and summary for human coach".
///
/// **Local only.** Notes contain injuries and pain levels, which is health
/// data — nothing here goes to a server unless the user explicitly shares it
/// with a coach they chose. Persisted through the `Preferences` KV seam, which
/// is UserDefaults on iOS and the durable SQLite store on Android (#1108).
public struct CoachNotes: Codable, Sendable, Equatable {

    /// A thing worth remembering, with when it was said. A note without a date
    /// is useless a month later — "back was sore" matters very differently if
    /// it was yesterday or in March.
    public struct Note: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var date: String        // yyyy-MM-dd
        public var text: String
        public var kind: Kind

        public enum Kind: String, Codable, Sendable {
            /// Answered during intake.
            case intake
            /// Mentioned in passing — the moments the operator wanted caught.
            case moment
            /// Something the coach concluded, not something the user said.
            case observation
        }

        public init(id: String = UUID().uuidString, date: String, text: String, kind: Kind) {
            self.id = id
            self.date = date
            self.text = text
            self.kind = kind
        }
    }

    public var intake = CoachIntake()
    public var notes: [Note] = []

    public init() {}

    // MARK: - Persistence

    private static let storageKey = "drift_coach_notes"

    public static func load() -> CoachNotes {
        guard let json = DriftPlatform.keyValueStore.string(forKey: storageKey),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(CoachNotes.self, from: data) else {
            return CoachNotes()
        }
        return decoded
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return }
        DriftPlatform.keyValueStore.set(json, forKey: Self.storageKey)
    }

    // MARK: - Recording

    /// Add a note and persist. Caps the log so a chatty year can't grow the
    /// store unbounded — the oldest MOMENTS drop first, while intake answers
    /// and observations are kept, because those are the durable facts.
    public mutating func record(_ text: String, kind: Note.Kind, on date: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        notes.append(Note(date: DateFormatters.dateOnly.string(from: date),
                          text: String(trimmed.prefix(500)), kind: kind))
        if notes.count > Self.maxNotes {
            var moments = notes.filter { $0.kind == .moment }
            let keepers = notes.filter { $0.kind != .moment }
            moments = Array(moments.suffix(max(0, Self.maxNotes - keepers.count)))
            notes = (keepers + moments).sorted { $0.date < $1.date }
        }
        save()
    }

    static let maxNotes = 200

    // MARK: - Handoff

    /// What Coach Me feeds back to the model as context, and what a human coach
    /// reads on day one. Recent moments first — a six-month-old note about a
    /// tweaked shoulder is history, last week's is a training constraint.
    public func briefing(recentLimit: Int = 20) -> String {
        var lines = ["Client summary: \(intake.summary)"]
        let recent = notes.suffix(recentLimit)
        if !recent.isEmpty {
            lines.append("")
            lines.append("Notes:")
            for note in recent.reversed() {
                lines.append("- \(note.date): \(note.text)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
