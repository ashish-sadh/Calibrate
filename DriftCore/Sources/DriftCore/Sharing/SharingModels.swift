import Foundation

/// Wire DTOs for the friends/trainer sharing backend (Supabase Postgres via
/// PostgREST). Field names are snake_case to match the server rows verbatim;
/// `SharingJSON` (below) configures the coder so we never hand-map keys.
///
/// These mirror `supabase/migrations/0001_sharing_core.sql`. Only sharable,
/// non-PII fields exist here — email/phone never cross this boundary.

public enum FriendStatus: String, Codable, Sendable {
    case pending, accepted, blocked
}

public enum FriendRole: String, Codable, Sendable {
    case friend, trainer
}

public enum ShareStatus: String, Codable, Sendable {
    case sent, accepted, declined
}

public enum SessionStatus: String, Codable, Sendable {
    case live, completed, abandoned
}

/// Public directory entry — the only thing other users ever see about you.
public struct SharedProfile: Codable, Sendable, Identifiable, Hashable {
    public let id: String                 // server auth uid (uuid)
    public var username: String
    public var displayName: String?
    public var avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }

    public init(id: String, username: String, displayName: String? = nil, avatarUrl: String? = nil) {
        self.id = id; self.username = username
        self.displayName = displayName; self.avatarUrl = avatarUrl
    }
}

/// A directed friend/trainer edge.
public struct FriendshipDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let requesterId: String
    public let addresseeId: String
    public var status: FriendStatus
    public var role: FriendRole

    enum CodingKeys: String, CodingKey {
        case id, status, role
        case requesterId = "requester_id"
        case addresseeId = "addressee_id"
    }
}

/// A template shared/assigned to a recipient. `exercisesJson` is Drift's
/// `[TemplateExercise]` shape, so accepting it is a direct decode → save.
public struct SharedTemplateDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let ownerId: String
    public let recipientId: String
    public var name: String
    public var exercisesJson: String
    public var note: String?
    public var status: ShareStatus

    enum CodingKeys: String, CodingKey {
        case id, name, note, status
        case ownerId = "owner_id"
        case recipientId = "recipient_id"
        case exercisesJson = "exercises_json"
    }

    /// Decode the embedded exercises for local `WorkoutTemplate` creation.
    public var exercises: [WorkoutTemplate.TemplateExercise] {
        guard let data = exercisesJson.data(using: .utf8),
              let list = try? JSONDecoder().decode([WorkoutTemplate.TemplateExercise].self, from: data)
        else { return [] }
        return list
    }
}

/// A client's session made visible to one trainer (live + completed).
public struct LiveWorkoutDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let clientId: String
    public let trainerId: String
    public var templateName: String?
    public var status: SessionStatus
    public var startedAt: String?
    public var endedAt: String?
    /// Where the session came from: `"drift"` for one logged in the app (sets,
    /// reps — what a coach programmed) or `"health"` for one imported from
    /// Apple Health / Health Connect (a walk the watch recorded).
    ///
    /// Optional and ABSENT-MEANS-DRIFT: every row written before the column
    /// existed was a manually logged Drift session, and treating those as
    /// imported would silence alerts a coach expects. The column arrives with
    /// the broadcast migration; decoding tolerates its absence so this ships
    /// safely ahead of it.
    public var source: String?

    enum CodingKeys: String, CodingKey {
        case id, status, source
        case clientId = "client_id"
        case trainerId = "trainer_id"
        case templateName = "template_name"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }

    /// True when this was imported rather than logged in Drift — the
    /// distinction that decides whether a coach is interrupted (#1162).
    public var isImported: Bool { source == "health" }

    /// Best timestamp for the activity feed: when it ended, else when it started.
    public var activityDate: Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for s in [endedAt, startedAt].compactMap({ $0 }) {
            if let d = iso.date(from: s) { return d }
            let plain = ISO8601DateFormatter()
            if let d = plain.date(from: s) { return d }
        }
        return nil
    }
}

public struct LiveWorkoutSetDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let liveWorkoutId: String
    public var exerciseName: String
    public var exerciseOrder: Int
    public var setOrder: Int
    public var weightLbs: Double?
    public var reps: Int?
    public var isWarmup: Bool
    public var done: Bool

    enum CodingKeys: String, CodingKey {
        case id, reps, done
        case liveWorkoutId = "live_workout_id"
        case exerciseName = "exercise_name"
        case exerciseOrder = "exercise_order"
        case setOrder = "set_order"
        case weightLbs = "weight_lbs"
        case isWarmup = "is_warmup"
    }
}

/// A direct chat message between two connected users.
public struct MessageDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let senderId: String
    public let recipientId: String
    public var body: String
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body
        case senderId = "sender_id"
        case recipientId = "recipient_id"
        case createdAt = "created_at"
    }

    public var date: Date? {
        guard let createdAt else { return nil }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt)
    }
}

/// A note a HUMAN coach wrote about their client (migration 0006). Distinct
/// from `CoachNotes.Note`, which the APP writes from the client's own words —
/// conflating the two is what made the briefing read as if the coach had
/// authored the AI's observations.
///
/// Always visible to the client: a note about someone they cannot read is a
/// file kept on a person, which is not what Drift is.
public struct CoachAuthoredNote: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let coachId: String
    public let clientId: String
    public var text: String
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, text
        case coachId = "coach_id"
        case clientId = "client_id"
        case createdAt = "created_at"
    }

    public init(id: String, coachId: String, clientId: String,
                text: String, createdAt: String? = nil) {
        self.id = id
        self.coachId = coachId
        self.clientId = clientId
        self.text = text
        self.createdAt = createdAt
    }

    /// yyyy-MM-dd for display — a coach note is a dated timeline entry, never
    /// an undated verdict.
    public var dateOnly: String {
        guard let createdAt else { return "" }
        return String(createdAt.prefix(10))
    }
}

/// A resolved connection with its relationship kind, for the Friends hub.
public struct Connection: Sendable, Identifiable, Hashable {
    public enum Kind: String, Sendable { case friend, coach, client }
    public let profile: SharedProfile
    public let kind: Kind
    public var id: String { profile.id }
    public init(profile: SharedProfile, kind: Kind) { self.profile = profile; self.kind = kind }
}

/// Shared coders for the sharing wire format. PostgREST returns/accepts plain
/// snake_case JSON; the DTO CodingKeys already map it, so these are stock.
public enum SharingJSON {
    public static let decoder = JSONDecoder()
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
}
