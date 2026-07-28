import Foundation

/// The friends & trainer feature's domain API. Owns the auth session (claim,
/// refresh, persist) and turns the plan's user stories into typed calls over
/// `SyncClient`. Everything is opt-in: the first network touch is `sendEmailCode`.
///
/// `@MainActor` because it reads/writes the durable `SharingSessionStore`
/// (which reaches `DriftPlatform.secureStore`, a main-actor seam) and is driven
/// straight from SwiftUI. Calls are buffered HTTPS — fine on both platforms.
@MainActor
public final class SharingService {

    public static let shared = SharingService()

    private let client: SyncClient
    private let db: AppDatabase

    public init(client: SyncClient = SyncClient(), db: AppDatabase = .shared) {
        self.client = client
        self.db = db
    }

    public var isConfigured: Bool { client.isConfigured }
    public var isSignedIn: Bool { SharingSessionStore.isSignedIn(db: db) }
    public var currentSession: SharingSession? { SharingSessionStore.load(db: db) }
    public var currentUsername: String? { currentSession?.username }

    // MARK: - Auth (username-only, anonymous account)

    /// Create an anonymous account — no email, no password. The server mints a
    /// real user + session (so Row-Level Security's `auth.uid()` works); the
    /// user's public identity is the @username they pick next. Device-bound:
    /// the session persists locally (SQLite + Keychain), so there's nothing to
    /// remember and nothing personal shared.
    @discardableResult
    public func signInAnonymously() async throws -> SharingSession {
        let obj = try await client.authPost("signup", body: [:])
        let session = try Self.parseSession(obj, previousUsername: currentUsername)
        SharingSessionStore.save(session, db: db)
        return session
    }

    /// The whole onboarding in one call: silently create the anonymous account
    /// if needed, then claim the chosen @username. This is all the user does —
    /// type a username and they're in.
    public func startSharing(username: String, displayName: String? = nil) async throws {
        if !isSignedIn { try await signInAnonymously() }
        try await claimUsername(username, displayName: displayName)
    }

    /// Sign out / switch identity. Because an anonymous account can't be signed
    /// back into, this frees the @username by deleting the profile server-side
    /// (best-effort) before clearing the local session — so the SAME username
    /// can be re-claimed on this device. Cascades remove friendships/shares.
    public func signOut() async {
        if let session = currentSession, let token = try? await validToken() {
            // Best-effort — the local session is cleared regardless.
            try? await client.restDelete("profiles?id=eq.\(session.userID)", token: token)
        }
        SharingSessionStore.clear(db: db)
    }

    // MARK: - Profile / directory

    /// Claim (or change) the caller's public @username. Throws `.conflict` when
    /// the handle is taken. `username` must match `^[a-z0-9_]{3,20}$` (server
    /// check) — normalize before calling.
    public func claimUsername(_ username: String, displayName: String? = nil) async throws {
        let uid = try requireUserID()
        var row: [String: Any] = ["id": uid, "username": username]
        if let displayName { row["display_name"] = displayName }
        let _: [SharedProfile] = try await client.restInsert("profiles", body: [row],
                                                             token: try await validToken(),
                                                             upsert: true)
        // Reflect the claimed handle into the durable session.
        if var s = currentSession { s.username = username; SharingSessionStore.save(s, db: db) }
    }

    /// Search the directory by username / display-name prefix. Excludes self.
    public func searchUsers(_ query: String) async throws -> [SharedProfile] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let token = try await validToken()
        let path = "profiles?or=(username.ilike.*\(q)*,display_name.ilike.*\(q)*)"
            + "&select=id,username,display_name,avatar_url&limit=25"
        let results: [SharedProfile] = try await client.restGet(path, token: token)
        let me = currentSession?.userID
        return results.filter { $0.id != me }
    }

    /// Batch-fetch profiles for a set of user IDs (to render friend rows).
    public func profiles(ids: [String]) async throws -> [SharedProfile] {
        guard !ids.isEmpty else { return [] }
        let list = ids.joined(separator: ",")
        let path = "profiles?id=in.(\(list))&select=id,username,display_name,avatar_url"
        return try await client.restGet(path, token: try await validToken())
    }

    // MARK: - Friend / trainer edges

    /// Send a friend (or trainer) request to another profile.
    public func sendRequest(to profileID: String, role: FriendRole = .friend) async throws {
        let uid = try requireUserID()
        let row: [String: Any] = [
            "requester_id": uid, "addressee_id": profileID, "role": role.rawValue,
        ]
        let _: [FriendshipDTO] = try await client.restInsert("friendships", body: [row],
                                                             token: try await validToken())
    }

    /// Requests awaiting the caller's decision.
    public func incomingRequests() async throws -> [FriendshipDTO] {
        let uid = try requireUserID()
        return try await client.restGet(
            "friendships?addressee_id=eq.\(uid)&status=eq.pending&select=*",
            token: try await validToken())
    }

    /// Accept or decline a pending request the caller received.
    public func respondToRequest(_ id: String, accept: Bool) async throws {
        let status = accept ? FriendStatus.accepted : .blocked
        let _: [FriendshipDTO] = try await client.restUpdate(
            "friendships?id=eq.\(id)", body: ["status": status.rawValue],
            token: try await validToken())
    }

    /// Accepted edges involving the caller (both directions).
    public func acceptedFriendships() async throws -> [FriendshipDTO] {
        let uid = try requireUserID()
        return try await client.restGet(
            "friendships?status=eq.accepted&or=(requester_id.eq.\(uid),addressee_id.eq.\(uid))&select=*",
            token: try await validToken())
    }

    // MARK: - Template sharing / assignment

    /// Share (friend) or assign (trainer) a local template to a recipient.
    /// `role=.trainer` marks it as a coach assignment; the recipient accepts it
    /// the same way. Records the local↔server link for de-dup.
    public func shareTemplate(_ template: WorkoutTemplate, to recipientID: String,
                              role: FriendRole = .friend, note: String? = nil) async throws {
        let uid = try requireUserID()
        var row: [String: Any] = [
            "owner_id": uid, "recipient_id": recipientID,
            "name": template.name, "exercises_json": template.exercisesJson,
        ]
        if let note { row["note"] = note }
        let inserted: [SharedTemplateDTO] = try await client.restInsert(
            "shared_templates", body: [row], token: try await validToken())
        if let localID = template.id, let serverID = inserted.first?.id {
            SyncMap.link(.template, localID: localID, serverUUID: serverID, db: db)
        }
    }

    /// Templates sent to the caller and not yet accepted/declined.
    public func incomingSharedTemplates() async throws -> [SharedTemplateDTO] {
        let uid = try requireUserID()
        return try await client.restGet(
            "shared_templates?recipient_id=eq.\(uid)&status=eq.sent&select=*",
            token: try await validToken())
    }

    /// Accept a shared template — materialize it as a real local `WorkoutTemplate`
    /// (so it appears in the library and runs like any other) and mark it accepted.
    @discardableResult
    public func acceptSharedTemplate(_ dto: SharedTemplateDTO) async throws -> WorkoutTemplate {
        var template = WorkoutTemplate(
            name: dto.name, exercisesJson: dto.exercisesJson,
            createdAt: DateFormatters.iso8601.string(from: Date()))
        try WorkoutService.saveTemplate(&template)
        if let localID = template.id {
            SyncMap.link(.template, localID: localID, serverUUID: dto.id, db: db)
        }
        let _: [SharedTemplateDTO] = try await client.restUpdate(
            "shared_templates?id=eq.\(dto.id)", body: ["status": ShareStatus.accepted.rawValue],
            token: try await validToken())
        return template
    }

    /// Decline a shared template (leaves the local library untouched).
    public func declineSharedTemplate(_ dto: SharedTemplateDTO) async throws {
        let _: [SharedTemplateDTO] = try await client.restUpdate(
            "shared_templates?id=eq.\(dto.id)", body: ["status": ShareStatus.declined.rawValue],
            token: try await validToken())
    }

    // MARK: - Trainer-visible sessions (live-watch + completed report)

    /// One completed set to hand to a friend (a flattened workout row).
    public struct SharedSet: Sendable {
        public let exerciseName: String
        public let exerciseOrder: Int
        public let setOrder: Int
        public let weightLbs: Double?
        public let reps: Int?
        public let isWarmup: Bool
        public init(exerciseName: String, exerciseOrder: Int, setOrder: Int,
                    weightLbs: Double?, reps: Int?, isWarmup: Bool) {
            self.exerciseName = exerciseName; self.exerciseOrder = exerciseOrder
            self.setOrder = setOrder; self.weightLbs = weightLbs
            self.reps = reps; self.isWarmup = isWarmup
        }
    }

    /// Send a FINISHED workout to a friend in one call — it appears in their app
    /// as a completed session from you. Opens the session, pushes every set, and
    /// marks it completed. This is the "workouts you do show up to friends" path;
    /// plain HTTPS, so it works on both platforms.
    public func shareCompletedWorkout(to friendID: String, workoutName: String,
                                      sets: [SharedSet]) async throws {
        let sid = try await startLiveSession(trainerID: friendID, templateName: workoutName)
        for s in sets {
            try await pushSet(sessionID: sid, exerciseName: s.exerciseName,
                              exerciseOrder: s.exerciseOrder, setOrder: s.setOrder,
                              weightLbs: s.weightLbs, reps: s.reps,
                              isWarmup: s.isWarmup, done: true)
        }
        try await endSession(sid, status: .completed)
    }

    /// Open a session the given trainer may watch/receive. Returns the server
    /// session id to push sets into.
    public func startLiveSession(trainerID: String, templateName: String?) async throws -> String {
        let uid = try requireUserID()
        var row: [String: Any] = ["client_id": uid, "trainer_id": trainerID, "status": SessionStatus.live.rawValue]
        if let templateName { row["template_name"] = templateName }
        let inserted: [LiveWorkoutDTO] = try await client.restInsert(
            "live_workouts", body: [row], token: try await validToken())
        guard let id = inserted.first?.id else { throw SharingError.decoding("no session id returned") }
        return id
    }

    /// Append one set to a live session (the trainer sees it via Realtime, or in
    /// the completed report). Safe to call as each set is finished.
    public func pushSet(sessionID: String, exerciseName: String, exerciseOrder: Int,
                        setOrder: Int, weightLbs: Double?, reps: Int?,
                        isWarmup: Bool, done: Bool) async throws {
        var row: [String: Any] = [
            "live_workout_id": sessionID, "exercise_name": exerciseName,
            "exercise_order": exerciseOrder, "set_order": setOrder,
            "is_warmup": isWarmup, "done": done,
        ]
        if let weightLbs { row["weight_lbs"] = weightLbs }
        if let reps { row["reps"] = reps }
        let _: [LiveWorkoutSetDTO] = try await client.restInsert(
            "live_workout_sets", body: [row], token: try await validToken())
    }

    /// Mark a session finished (or abandoned) — this is what makes it a
    /// "completed report" in the trainer's app.
    public func endSession(_ sessionID: String, status: SessionStatus = .completed) async throws {
        let _: [LiveWorkoutDTO] = try await client.restUpdate(
            "live_workouts?id=eq.\(sessionID)",
            body: ["status": status.rawValue, "ended_at": DateFormatters.iso8601.string(from: Date())],
            token: try await validToken())
    }

    /// Sessions from the caller's clients (trainer view), newest first.
    public func clientSessions() async throws -> [LiveWorkoutDTO] {
        let uid = try requireUserID()
        return try await client.restGet(
            "live_workouts?trainer_id=eq.\(uid)&select=*&order=started_at.desc&limit=100",
            token: try await validToken())
    }

    /// All sets of a session (for the live mirror / completed report body).
    public func sessionSets(_ sessionID: String) async throws -> [LiveWorkoutSetDTO] {
        try await client.restGet(
            "live_workout_sets?live_workout_id=eq.\(sessionID)&select=*&order=exercise_order.asc,set_order.asc",
            token: try await validToken())
    }

    // MARK: - Session / token helpers

    private func requireUserID() throws -> String {
        guard let uid = currentSession?.userID else { throw SharingError.notSignedIn }
        return uid
    }

    /// A non-expired access token, refreshing via the refresh token when due.
    private func validToken() async throws -> String {
        guard let session = currentSession else { throw SharingError.notSignedIn }
        guard session.isExpired() else { return session.accessToken }
        guard let refresh = session.refreshToken else { throw SharingError.notSignedIn }
        let obj = try await client.authPost("token?grant_type=refresh_token",
                                            body: ["refresh_token": refresh])
        let refreshed = try Self.parseSession(obj, previousUsername: session.username)
        SharingSessionStore.save(refreshed, db: db)
        return refreshed.accessToken
    }

    /// Parse a GoTrue token bundle into a `SharingSession`. `username` isn't in
    /// the auth response, so carry it forward from the prior session.
    static func parseSession(_ obj: [String: Any], previousUsername: String?) throws -> SharingSession {
        guard let accessToken = obj["access_token"] as? String else {
            let msg = (obj["error_description"] as? String) ?? (obj["msg"] as? String) ?? "no access_token"
            throw SharingError.http(400, msg)
        }
        let user = obj["user"] as? [String: Any]
        guard let userID = user?["id"] as? String else {
            throw SharingError.decoding("auth response missing user id")
        }
        let expiresAt: Date?
        if let secs = obj["expires_in"] as? Double {
            expiresAt = Date().addingTimeInterval(secs)
        } else if let at = obj["expires_at"] as? Double {
            expiresAt = Date(timeIntervalSince1970: at)
        } else {
            expiresAt = nil
        }
        return SharingSession(
            userID: userID, username: previousUsername,
            accessToken: accessToken, refreshToken: obj["refresh_token"] as? String,
            expiresAt: expiresAt)
    }
}
