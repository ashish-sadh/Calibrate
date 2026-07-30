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
        // `discoverable=is.true` is the public-profile switch (migration 0007):
        // hidden accounts are reachable by invite link but never surfaced by
        // search. Enforced in the query, not by RLS, because a hidden profile
        // must stay READABLE BY ID — otherwise someone who connected via your
        // link could never see your name.
        let path = "profiles?discoverable=is.true"
            + "&or=(username.ilike.*\(q)*,display_name.ilike.*\(q)*)"
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

    // MARK: - Discovery (invite links + the public-profile switch)

    /// Resolve one profile by @handle — how an invite link becomes a person.
    /// Deliberately ignores `discoverable`: someone who sent you their link
    /// wants to be found by it, and hiding means "keep me out of search", not
    /// "break my own invites".
    public func profile(username: String) async throws -> SharedProfile? {
        let handle = InviteLink.normalize(username)
        guard !handle.isEmpty else { return nil }
        let rows: [SharedProfile] = try await client.restGet(
            "profiles?username=eq.\(handle)&select=id,username,display_name,avatar_url&limit=1",
            token: try await validToken())
        return rows.first
    }

    /// Whether the caller is currently listed in search.
    public func isDiscoverable() async throws -> Bool {
        let uid = try requireUserID()
        struct Row: Codable { let discoverable: Bool? }
        let rows: [Row] = try await client.restGet(
            "profiles?id=eq.\(uid)&select=discoverable&limit=1",
            token: try await validToken())
        // Absent reads as listed, matching the column default: an account made
        // before the column existed was always searchable.
        return rows.first?.discoverable ?? true
    }

    /// Turn search listing on or off. Existing connections are unaffected.
    public func setDiscoverable(_ discoverable: Bool) async throws {
        let uid = try requireUserID()
        let _: [SharedProfile] = try await client.restUpdate(
            "profiles?id=eq.\(uid)", body: ["discoverable": discoverable],
            token: try await validToken())
    }

    /// Every pending edge involving the caller, either direction. Search needs
    /// this to say "Requested" for someone asked days ago — `requestedIDs` only
    /// remembers taps made in the current session.
    public func pendingEdges() async throws -> [FriendshipDTO] {
        let uid = try requireUserID()
        return try await client.restGet(
            "friendships?status=eq.pending&or=(requester_id.eq.\(uid),addressee_id.eq.\(uid))&select=*",
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

    /// Add someone as YOUR coach (they monitor your workouts + can assign +
    /// chat). Modeled as a trainer edge with you as the requester/client.
    public func addCoach(_ profileID: String) async throws {
        try await sendRequest(to: profileID, role: .trainer)
    }

    // MARK: - Managing existing connections (operator 2026-07-29: "no flow to
    // unfriend, remove a coach, or make an existing friend a coach")

    /// Every edge between the caller and one person, whatever the status —
    /// management needs pending and blocked edges too, not just accepted.
    func edges(with profileID: String) async throws -> [FriendshipDTO] {
        let uid = try requireUserID()
        return try await client.restGet(
            "friendships?or=(and(requester_id.eq.\(uid),addressee_id.eq.\(profileID)),and(requester_id.eq.\(profileID),addressee_id.eq.\(uid)))&select=*",
            token: try await validToken())
    }

    /// Ask an existing friend to BECOME your coach. A request, not an action
    /// (operator decision 2026-07-29: coaching is a relationship the other
    /// person accepts, never an imposed role). Creates a pending trainer edge
    /// — the friendship stays untouched and intact while they decide, and
    /// their requests card reads "wants you as their coach". Requires the
    /// 0003 migration (edge uniqueness includes role) so the pending edge can
    /// coexist with the friend edge.
    public func requestCoachPromotion(_ profileID: String) async throws {
        try await sendRequest(to: profileID, role: .trainer)
    }

    /// Turn your coach back into a plain friend, and revoke the briefing so no
    /// stale picture of you survives the demotion.
    public func demoteCoach(_ profileID: String) async throws {
        let uid = try requireUserID()
        let all = try await edges(with: profileID)
        let hasFriendEdge = all.contains { $0.role == .friend && $0.status == .accepted }
        for edge in all where edge.role == .trainer
            && edge.requesterId == uid && edge.addresseeId == profileID {
            if hasFriendEdge {
                // A friendship exists underneath — drop the trainer edge.
                try await client.restDelete("friendships?id=eq.\(edge.id)",
                                            token: try await validToken())
            } else {
                let _: [FriendshipDTO] = try await client.restUpdate(
                    "friendships?id=eq.\(edge.id)",
                    body: ["role": FriendRole.friend.rawValue],
                    token: try await validToken())
            }
        }
        try? await revokeBriefing(from: profileID)
    }

    /// Remove every edge with this person — unfriend, drop a client, or fully
    /// disconnect from a coach. Pending and blocked edges go too, so nothing
    /// resurrects later. Either party may delete an edge (RLS). When a coach
    /// relationship existed, the briefing is revoked with it.
    public func removeConnection(with profileID: String) async throws {
        let uid = try requireUserID()
        let all = try await edges(with: profileID)
        let hadCoach = all.contains {
            $0.role == .trainer && $0.status == .accepted
                && $0.requesterId == uid && $0.addresseeId == profileID
        }
        for edge in all {
            try await client.restDelete("friendships?id=eq.\(edge.id)",
                                        token: try await validToken())
        }
        if hadCoach { try? await revokeBriefing(from: profileID) }
    }

    /// All accepted connections, resolved to profiles + relationship kind:
    /// `.friend` (mutual), `.coach` (they coach you), `.client` (you coach them).
    public func connections() async throws -> [Connection] {
        let uid = try requireUserID()
        let edges = try await acceptedFriendships()
        let otherIDs = edges.map { $0.requesterId == uid ? $0.addresseeId : $0.requesterId }
        let profs = try await profiles(ids: otherIDs)
        let byID = Dictionary(profs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let resolved = edges.compactMap { e -> Connection? in
            let otherID = e.requesterId == uid ? e.addresseeId : e.requesterId
            guard let p = byID[otherID] else { return nil }
            let kind: Connection.Kind
            if e.role == .trainer {
                // trainer edge: requester = client, addressee = coach.
                kind = (e.requesterId == uid) ? .coach : .client
            } else {
                kind = .friend
            }
            return Connection(profile: p, kind: kind)
        }
        // A person can carry two edges (a friendship one way + a trainer edge
        // the other, after promoteToCoach). One row per person, and the
        // coach/client kind is the one that matters.
        var seen: [String: Connection] = [:]
        var order: [String] = []
        for connection in resolved {
            if let existing = seen[connection.id] {
                if existing.kind == .friend && connection.kind != .friend {
                    seen[connection.id] = connection
                }
            } else {
                seen[connection.id] = connection
                order.append(connection.id)
            }
        }
        return order.compactMap { seen[$0] }
    }

    // MARK: - Coach-authored notes (the other direction: coach → client)

    /// Notes written BY a human coach ABOUT one client, newest first. Readable
    /// by both parties — a coach reads their own log, the client reads what
    /// their coach wrote about them. There is no private-to-coach mode by
    /// design (migration 0006).
    public func coachNotes(clientID: String, coachID: String) async throws -> [CoachAuthoredNote] {
        let rows: [CoachAuthoredNote] = try await client.restGet(
            "coach_notes?client_id=eq.\(clientID)&coach_id=eq.\(coachID)&select=*&order=created_at.desc",
            token: try await validToken())
        return rows
    }

    /// Every note written about the CALLER, across all their coaches — what a
    /// client sees on their own sharing card.
    public func notesAboutMe() async throws -> [CoachAuthoredNote] {
        let uid = try requireUserID()
        return try await client.restGet(
            "coach_notes?client_id=eq.\(uid)&select=*&order=created_at.desc",
            token: try await validToken())
    }

    /// Write a note about a client. The caller must be their coach; RLS
    /// enforces it, so a stale UI can't write onto a stranger.
    public func addCoachNote(clientID: String, text: String) async throws {
        let uid = try requireUserID()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let row: [String: Any] = [
            "coach_id": uid, "client_id": clientID,
            // Cap it: this is a training note, not a document, and an
            // unbounded field is an unbounded row.
            "text": String(trimmed.prefix(1000)),
        ]
        let _: [CoachAuthoredNote] = try await client.restInsert(
            "coach_notes", body: [row], token: try await validToken())
    }

    /// Retract (coach) or remove (client) — either party may delete, neither
    /// may rewrite the other's words.
    public func deleteCoachNote(_ id: String) async throws {
        try await client.restDelete("coach_notes?id=eq.\(id)", token: try await validToken())
    }

    // MARK: - Client briefing (what a coach sees beyond the workouts)

    /// Push the client's briefing to one coach. `level` decides what is
    /// included; anything not opted into is never serialized, so a withheld
    /// category leaves no trace in the request body — the filtering is not a
    /// server-side courtesy.
    ///
    /// Upserts on (client_id, coach_id): the coach reads the current picture,
    /// not an append-only history they'd have to page through.
    public func shareBriefing(with coachID: String,
                              level: BriefingSharingLevel,
                              notes: CoachNotes,
                              metrics: BriefingMetrics) async throws {
        let uid = try requireUserID()
        let sharesHistory = level.contains(.history)
        let row: [String: Any] = [
            "client_id": uid,
            "coach_id": coachID,
            "summary": sharesHistory ? notes.intake.summary : "",
            "notes": sharesHistory ? notes.notes.map(Self.noteRow) : [],
            "metrics": metrics.payload,
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ]
        try await client.restUpsertDiscard("client_briefings", body: [row],
                                           token: try await validToken())
    }

    /// Withdraw everything shared with one coach. Deletes rather than blanks
    /// the row: "I revoked this" should leave nothing behind, and an empty row
    /// still tells the coach a relationship once had data in it.
    public func revokeBriefing(from coachID: String) async throws {
        let uid = try requireUserID()
        BriefingSharingLevel.none.store(for: coachID)
        try await client.restDelete(
            "client_briefings?client_id=eq.\(uid)&coach_id=eq.\(coachID)",
            token: try await validToken())
    }

    /// The coach's read of one client. Nil when that client has shared nothing —
    /// the caller shows "nothing shared yet" rather than an empty card that
    /// looks like a client with no data.
    public func fetchBriefing(for clientID: String) async throws -> ClientBriefing? {
        let uid = try requireUserID()
        let rows: [[String: Any]] = try await client.restGetRaw(
            "client_briefings?coach_id=eq.\(uid)&client_id=eq.\(clientID)&select=*",
            token: try await validToken())
        guard let row = rows.first else { return nil }
        return Self.parseBriefing(row, clientID: clientID)
    }

    nonisolated static func noteRow(_ note: CoachNotes.Note) -> [String: Any] {
        ["id": note.id, "date": note.date, "text": note.text, "kind": note.kind.rawValue]
    }

    nonisolated static func parseBriefing(_ row: [String: Any], clientID: String) -> ClientBriefing {
        let noteRows = (row["notes"] as? [[String: Any]]) ?? []
        let notes: [CoachNotes.Note] = noteRows.compactMap { item in
            guard let text = item["text"] as? String, let date = item["date"] as? String else { return nil }
            let kind = (item["kind"] as? String).flatMap(CoachNotes.Note.Kind.init) ?? .moment
            return CoachNotes.Note(id: (item["id"] as? String) ?? UUID().uuidString,
                                   date: date, text: text, kind: kind)
        }
        return ClientBriefing(
            clientID: clientID,
            summary: (row["summary"] as? String) ?? "",
            notes: notes,
            metrics: BriefingMetrics.decode((row["metrics"] as? [String: Any]) ?? [:]),
            updatedAt: row["updated_at"] as? String)
    }

    // MARK: - Chat (direct messages)

    /// Send a chat message to a connected user.
    @discardableResult
    public func sendMessage(to recipientID: String, body: String) async throws -> MessageDTO {
        let uid = try requireUserID()
        let trimmed = String(body.prefix(2000))
        let row: [String: Any] = ["sender_id": uid, "recipient_id": recipientID, "body": trimmed]
        let inserted: [MessageDTO] = try await client.restInsert("messages", body: [row],
                                                                 token: try await validToken())
        guard let msg = inserted.first else { throw SharingError.decoding("no message returned") }
        return msg
    }

    /// The conversation with another user, oldest first (most recent 200).
    /// Fetches newest-first then reverses — `asc&limit=200` returned the FIRST
    /// 200 messages ever, so once a conversation passed 200 the poll re-read
    /// the same stale page forever and new messages never appeared.
    /// Everything recently sent TO the caller, across all correspondents — one
    /// round trip for the Today card instead of one fetch per connection.
    /// `Inbox.entries` groups it into newest-per-person with unread counts.
    public func recentInbox(limit: Int = 100) async throws -> [MessageDTO] {
        let uid = try requireUserID()
        return try await client.restGet(
            "messages?recipient_id=eq.\(uid)&select=*&order=created_at.desc&limit=\(limit)",
            token: try await validToken())
    }

    public func fetchMessages(with otherID: String) async throws -> [MessageDTO] {
        let uid = try requireUserID()
        let filter = "or=(and(sender_id.eq.\(uid),recipient_id.eq.\(otherID)),"
            + "and(sender_id.eq.\(otherID),recipient_id.eq.\(uid)))"
        let newestFirst: [MessageDTO] = try await client.restGet(
            "messages?\(filter)&select=*&order=created_at.desc&limit=200",
            token: try await validToken())
        return newestFirst.reversed()
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
        do {
            for s in sets {
                try await pushSet(sessionID: sid, exerciseName: s.exerciseName,
                                  exerciseOrder: s.exerciseOrder, setOrder: s.setOrder,
                                  weightLbs: s.weightLbs, reps: s.reps,
                                  isWarmup: s.isWarmup, done: true)
            }
        } catch {
            // A half-pushed session must not sit status=live forever in the
            // friend's feed ("is doing Leg Day 🔴" for days) — best-effort
            // close it as abandoned, then surface the original failure so the
            // caller's retry creates a fresh session.
            try? await endSession(sid, status: .abandoned)
            throw error
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

    /// In-flight refresh, so concurrent callers (e.g. the 3s chat poll + a send)
    /// don't each spend the SAME rotating refresh token — the second spend would
    /// fail and wrongly nuke the session ("DB/connection error after long chat").
    private var refreshInFlight: Task<String, Error>?

    /// A non-expired access token, refreshing via the refresh token when due.
    /// If the refresh FAILS (deleted account / dead refresh token) the stale
    /// session is CLEARED so the UI recovers to the username picker instead of
    /// looping on a credential-refresh error. #credential-refresh-recovery
    private func validToken() async throws -> String {
        guard let session = currentSession else { throw SharingError.notSignedIn }
        guard session.isExpired() else { return session.accessToken }
        // Coalesce: if a refresh is already running, await its result.
        if let inflight = refreshInFlight { return try await inflight.value }
        guard let refresh = session.refreshToken else {
            SharingSessionStore.clear(db: db); throw SharingError.notSignedIn
        }
        let task = Task<String, Error> { @MainActor [client, db] in
            do {
                let obj = try await client.authPost("token?grant_type=refresh_token",
                                                    body: ["refresh_token": refresh])
                let refreshed = try Self.parseSession(obj, previousUsername: session.username)
                SharingSessionStore.save(refreshed, db: db)
                return refreshed.accessToken
            } catch let e as SharingError {
                // A network blip must NOT nuke the session; only an auth
                // rejection (dead/rotated refresh token, deleted user) does.
                if case .network = e { throw e }
                SharingSessionStore.clear(db: db)
                throw SharingError.notSignedIn
            }
        }
        refreshInFlight = task
        defer { refreshInFlight = nil }
        return try await task.value
    }

    /// True if the stored session is still usable. Refreshes if expiring, and —
    /// when a username was claimed — confirms the profile still exists (catches
    /// an account deleted/wiped server-side). Clears a dead session as a side
    /// effect, so callers can fall back to the username picker. Never throws.
    public func validateSession() async -> Bool {
        guard let session = currentSession else { return false }
        do {
            let token = try await validToken()
            if session.username != nil {
                // Select id,username so the row decodes as SharedProfile
                // (username is required) — selecting only id fails to decode.
                let mine: [SharedProfile] = try await client.restGet(
                    "profiles?id=eq.\(session.userID)&select=id,username", token: token)
                if mine.isEmpty { SharingSessionStore.clear(db: db); return false }
            }
            return true
        } catch let e as SharingError {
            if case .network = e { return true }   // offline — keep the session
            SharingSessionStore.clear(db: db)
            return false
        } catch {
            return false
        }
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
