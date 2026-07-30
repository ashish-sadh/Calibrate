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
    /// Optional one-line bio (migration 0019). Decodes as nil when a row
    /// predates the column or a client never selected it.
    public var tagline: String?

    enum CodingKeys: String, CodingKey {
        case id, username, tagline
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }

    public init(id: String, username: String, displayName: String? = nil,
                avatarUrl: String? = nil, tagline: String? = nil) {
        self.id = id; self.username = username
        self.displayName = displayName; self.avatarUrl = avatarUrl
        self.tagline = tagline
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

/// A row of the `unread_counts` view (migration 0010): how many messages one
/// correspondent has sent you since you last read them, and when the newest
/// arrived. Exact — no client-side window.
public struct UnreadCountDTO: Codable, Sendable, Identifiable, Hashable {
    public let readerId: String
    public let peerId: String
    public let unread: Int
    public let latestAt: String?

    public var id: String { peerId }

    enum CodingKeys: String, CodingKey {
        case readerId = "reader_id"
        case peerId = "peer_id"
        case unread
        case latestAt = "latest_at"
    }

    public init(readerId: String, peerId: String, unread: Int, latestAt: String? = nil) {
        self.readerId = readerId
        self.peerId = peerId
        self.unread = unread
        self.latestAt = latestAt
    }
}

/// A `message_reads` row — the per-conversation read watermark.
public struct UnreadMarkDTO: Codable, Sendable, Hashable {
    public let readerId: String
    public let peerId: String
    public let readThrough: String

    enum CodingKeys: String, CodingKey {
        case readerId = "reader_id"
        case peerId = "peer_id"
        case readThrough = "read_through"
    }
}

/// A row from `public_activity` (migration 0012) — the only thing a stranger
/// reached from a global board can see. Name and date, nothing else: enough to
/// tell whether someone trains the way you do, which is the whole job.
public struct PublicActivityDTO: Codable, Sendable, Hashable, Identifiable {
    public let name: String
    public let workoutDate: String

    public var id: String { "\(workoutDate)-\(name)" }

    enum CodingKeys: String, CodingKey {
        case name
        case workoutDate = "workout_date"
    }

    public init(name: String, workoutDate: String) {
        self.name = name
        self.workoutDate = workoutDate
    }
}

/// Who a client-owned workout is for (migration 0014).
///
/// STORED rather than derived, because the completion sheet's two switches can
/// express "coaches but not friends" and a purely relationship-derived audience
/// cannot. The server intersects this with the relationships that exist at read
/// time, so a coach who arrives later still sees it and one who leaves stops.
public enum WorkoutAudience: String, Sendable, Equatable {
    /// Friends (rolling 30 days) and any current coach (full history).
    case all
    /// Coaches only — "share with friends" off, "share with coach" on.
    case coaches
    /// Friends only — "share with friends" on, "share with coach" OFF.
    ///
    /// Added 0017. This used to map to `.all`, which handed the session to the
    /// coach anyway: the switch did nothing and the completion sheet reported
    /// otherwise. The operator's words were "sometimes I might be testing and
    /// only want to share with friends but not trainer" — this is that state.
    case friends
    /// Nobody. Saved locally, never published.
    case `private`

    /// The audience implied by the two completion-sheet switches. Four states in,
    /// four out — no combination collapses into another.
    public static func from(friends: Bool, coaches: Bool) -> WorkoutAudience {
        switch (friends, coaches) {
        case (true, true):   return .all
        case (true, false):  return .friends
        case (false, true):  return .coaches
        case (false, false): return .private
        }
    }
}

/// A `coach_history_grants` row (migration 0015). `historyFrom == nil` means
/// FOREVER — the client handed over their whole training past. The ABSENCE of a
/// row means something different: only what happened since the coaching
/// relationship began.
public struct HistoryGrantDTO: Codable, Sendable, Hashable {
    public let clientId: String
    public let coachId: String
    public let historyFrom: String?

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case coachId = "coach_id"
        case historyFrom = "history_from"
    }
}
