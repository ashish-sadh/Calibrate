import Foundation
import GRDB
import Testing
@testable import DriftCore

/// Tier-0: `SharingService` request-building + session/token handling against a
/// mock `HTTPDataSession` — no live network. The live Supabase contract (RLS,
/// auth) is smoke-tested out-of-band; here we pin the client's own behavior.
@MainActor
struct SharingServiceTests {

    /// Records outgoing requests and replays a FIFO queue of canned responses.
    final class MockHTTP: HTTPDataSession, @unchecked Sendable {
        var queue: [(Int, Any)] = []
        private(set) var requests: [URLRequest] = []
        private let lock = NSLock()

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            lock.lock(); defer { lock.unlock() }
            requests.append(request)
            let (status, json): (Int, Any) = queue.isEmpty ? (200, [Any]()) : queue.removeFirst()
            let data = try JSONSerialization.data(withJSONObject: json)
            let resp = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
            return (data, resp)
        }

        var lastBody: [String: Any]? {
            guard let body = requests.last?.httpBody,
                  let obj = try? JSONSerialization.jsonObject(with: body) else { return nil }
            if let arr = obj as? [[String: Any]] { return arr.first }
            return obj as? [String: Any]
        }
    }

    private func makeService(_ mock: MockHTTP) throws -> (SharingService, AppDatabase) {
        let db = try AppDatabase.empty()
        let client = SyncClient(baseURL: "https://x.supabase.co", anonKey: "anon-key",
                                session: mock)
        return (SharingService(client: client, db: db), db)
    }

    private func signIn(_ svc: SharingService, db: AppDatabase, username: String? = "me") {
        SharingSessionStore.save(
            .init(userID: "me", username: username, accessToken: "AT",
                  refreshToken: "RT", expiresAt: Date().addingTimeInterval(3600)),
            db: db)
    }

    // MARK: Auth

    @Test func anonymousSignInPersistsSession() async throws {
        let mock = MockHTTP()
        mock.queue = [(200, [
            "access_token": "AT-1", "refresh_token": "RT-1", "expires_in": 3600,
            "user": ["id": "uid-42", "is_anonymous": true],
        ] as [String: Any])]
        let (svc, db) = try makeService(mock)

        let session = try await svc.signInAnonymously()
        #expect(session.userID == "uid-42")
        #expect(session.accessToken == "AT-1")
        #expect(SharingSessionStore.load(db: db)?.userID == "uid-42")
        // Anonymous sign-in hits the signup endpoint with the anon apikey.
        #expect(mock.requests.last?.url?.absoluteString.contains("/auth/v1/signup") == true)
        #expect(mock.requests.last?.value(forHTTPHeaderField: "apikey") == "anon-key")
    }

    @Test func startSharingSignsInThenClaims() async throws {
        let mock = MockHTTP()
        mock.queue = [
            (200, ["access_token": "AT", "refresh_token": "RT", "expires_in": 3600,
                   "user": ["id": "uid-9"]] as [String: Any]),          // signup
            (201, [["id": "uid-9", "username": "ashish"]] as [[String: Any]]),  // claim
        ]
        let (svc, db) = try makeService(mock)

        try await svc.startSharing(username: "ashish")
        #expect(mock.requests.first?.url?.absoluteString.contains("/auth/v1/signup") == true)
        #expect(mock.requests.last?.url?.absoluteString.contains("/rest/v1/profiles") == true)
        #expect(SharingSessionStore.load(db: db)?.username == "ashish")
    }

    @Test func authedCallWithoutSessionThrows() async throws {
        let mock = MockHTTP()
        let (svc, _) = try makeService(mock)
        await #expect(throws: SharingError.notSignedIn) {
            _ = try await svc.incomingRequests()
        }
    }

    // MARK: Profile / search

    @Test func claimUsernameUpsertsAndUpdatesSession() async throws {
        let mock = MockHTTP()
        mock.queue = [(201, [["id": "me", "username": "ashish"]] as [[String: Any]])]
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db, username: nil)

        try await svc.claimUsername("ashish", displayName: "Ash")
        let req = try #require(mock.requests.last)
        #expect(req.url?.absoluteString.contains("/rest/v1/profiles") == true)
        #expect(req.value(forHTTPHeaderField: "Prefer")?.contains("merge-duplicates") == true)
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer AT")
        #expect(mock.lastBody?["username"] as? String == "ashish")
        #expect(mock.lastBody?["display_name"] as? String == "Ash")
        #expect(SharingSessionStore.load(db: db)?.username == "ashish")
    }

    /// A tagline write must PATCH the existing row, never upsert. A PostgREST
    /// upsert (POST + merge-duplicates) feeds {id, tagline} into
    /// INSERT ... ON CONFLICT, and Postgres validates the insert tuple before
    /// the conflict can redirect to UPDATE — so `username` NOT NULL rejects it
    /// and every tagline save 400'd server-side. (#1173, reproduced against the
    /// live DB 2026-07-31.)
    @Test func setTaglinePatchesProfileRowInsteadOfUpserting() async throws {
        let mock = MockHTTP()
        mock.queue = [(200, [["id": "me", "username": "ashish",
                              "tagline": "deadlift + pole"]] as [[String: Any]])]
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db, username: "ashish")

        let updated = try await svc.setTagline("  deadlift + pole  ")
        let req = try #require(mock.requests.last)
        #expect(req.httpMethod == "PATCH", "must not be a POST upsert")
        #expect(req.url?.absoluteString.contains("profiles?id=eq.me") == true)
        #expect(req.value(forHTTPHeaderField: "Prefer")?.contains("merge-duplicates") != true)
        // Trimmed, and the body carries ONLY the tagline column — no username,
        // which is exactly what the NOT NULL insert path choked on.
        #expect(mock.lastBody?["tagline"] as? String == "deadlift + pole")
        #expect(mock.lastBody?["id"] == nil)
        #expect(updated?.tagline == "deadlift + pole")
    }

    /// Clearing must send an explicit null, not drop the key — a bare `{}` PATCH
    /// would leave the old tagline in place and "clear it" would do nothing.
    @Test func clearingTaglineSendsExplicitNull() async throws {
        let mock = MockHTTP()
        mock.queue = [(200, [["id": "me", "username": "ashish"]] as [[String: Any]])]
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db, username: "ashish")

        _ = try await svc.setTagline("   ")
        #expect(mock.requests.last?.httpMethod == "PATCH")
        #expect(mock.lastBody?["tagline"] is NSNull)
    }

    @Test func searchExcludesSelfAndBuildsIlike() async throws {
        let mock = MockHTTP()
        mock.queue = [(200, [
            ["id": "me", "username": "me_user"],
            ["id": "other", "username": "friend"],
        ] as [[String: Any]])]
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db)

        let results = try await svc.searchUsers("Fr")
        #expect(results.map(\.id) == ["other"])
        #expect(mock.requests.last?.url?.absoluteString.contains("ilike.*fr*") == true)
    }

    @Test func emptySearchSkipsNetwork() async throws {
        let mock = MockHTTP()
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db)
        let results = try await svc.searchUsers("   ")
        #expect(results.isEmpty)
        #expect(mock.requests.isEmpty)
    }

    // MARK: Template accept → real local template

    @Test func acceptSharedTemplateMaterializesLocalTemplate() async throws {
        let mock = MockHTTP()
        // PATCH ...return=representation echoes the full row.
        mock.queue = [(200, [[
            "id": "srv-1", "owner_id": "coach", "recipient_id": "me",
            "name": "Coach Push", "exercises_json": "[]", "status": "accepted",
        ]] as [[String: Any]])]
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db)

        let dto = SharedTemplateDTO(
            id: "srv-1", ownerId: "coach", recipientId: "me", name: "Coach Push",
            exercisesJson: #"[{"name":"Bench Press","sets":3}]"#, note: "heavy", status: .sent)

        let template = try await svc.acceptSharedTemplate(dto)
        #expect(template.name == "Coach Push")
        #expect(template.exercises.first?.name == "Bench Press")
        // It's a real row in the local library.
        let saved = try WorkoutService.fetchTemplates().first { $0.name == "Coach Push" }
        #expect(saved != nil)
        // And the local↔server link is recorded.
        if let localID = template.id {
            #expect(SyncMap.serverUUID(.template, localID: localID, db: db) == "srv-1")
        }
        // Status PATCH went out.
        #expect(mock.requests.last?.httpMethod == "PATCH")
        #expect(mock.lastBody?["status"] as? String == "accepted")
    }

    // MARK: Chat

    @Test func fetchMessagesRequestsNewestPageButReturnsOldestFirst() async throws {
        let mock = MockHTTP()
        // Server answers newest-first (created_at.desc) — the client must
        // reverse so the UI renders oldest-first.
        mock.queue = [(200, [
            ["id": "m2", "sender_id": "me", "recipient_id": "friend", "body": "second",
             "created_at": "2026-07-28T10:01:00Z"],
            ["id": "m1", "sender_id": "friend", "recipient_id": "me", "body": "first",
             "created_at": "2026-07-28T10:00:00Z"],
        ] as [[String: Any]])]
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db)

        let messages = try await svc.fetchMessages(with: "friend")
        #expect(messages.map(\.id) == ["m1", "m2"])
        // The page must be the NEWEST 200 — asc&limit re-read the first 200
        // messages ever, freezing long conversations.
        let url = try #require(mock.requests.last?.url?.absoluteString)
        #expect(url.contains("order=created_at.desc"))
        #expect(url.contains("limit=200"))
    }

    // MARK: Live session

    @Test func startLiveSessionReturnsServerID() async throws {
        let mock = MockHTTP()
        mock.queue = [(201, [["id": "live-9", "client_id": "me", "trainer_id": "coach", "status": "live"]] as [[String: Any]])]
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db)

        let id = try await svc.startLiveSession(trainerID: "coach", templateName: "Leg Day")
        #expect(id == "live-9")
        #expect(mock.lastBody?["trainer_id"] as? String == "coach")
        #expect(mock.lastBody?["status"] as? String == "live")
    }

    @Test func shareCompletedWorkoutStartsPushesEnds() async throws {
        let mock = MockHTTP()
        mock.queue = [
            (201, [["id": "sess-1", "client_id": "me", "trainer_id": "coach", "status": "live"]] as [[String: Any]]),
            (201, [["id": "set-1", "live_workout_id": "sess-1", "exercise_name": "Bench Press",
                    "exercise_order": 0, "set_order": 1, "is_warmup": false, "done": true]] as [[String: Any]]),
            (201, [["id": "set-2", "live_workout_id": "sess-1", "exercise_name": "Bench Press",
                    "exercise_order": 0, "set_order": 2, "is_warmup": false, "done": true]] as [[String: Any]]),
            (200, [["id": "sess-1", "client_id": "me", "trainer_id": "coach", "status": "completed"]] as [[String: Any]]),
        ]
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db)

        try await svc.shareCompletedWorkout(to: "coach", workoutName: "Push Day", sets: [
            .init(exerciseName: "Bench Press", exerciseOrder: 0, setOrder: 1, weightLbs: 135, reps: 10, isWarmup: false),
            .init(exerciseName: "Bench Press", exerciseOrder: 0, setOrder: 2, weightLbs: 155, reps: 8, isWarmup: false),
        ])
        // start(live_workouts) + 2×pushSet(live_workout_sets) + end(PATCH).
        #expect(mock.requests.count == 4)
        #expect(mock.requests[0].url?.absoluteString.contains("live_workouts") == true)
        #expect(mock.requests[1].url?.absoluteString.contains("live_workout_sets") == true)
        #expect(mock.requests[3].httpMethod == "PATCH")
        #expect(mock.lastBody?["status"] as? String == "completed")
    }

    @Test func shareCompletedWorkoutAbandonsSessionWhenAPushFails() async throws {
        let mock = MockHTTP()
        mock.queue = [
            (201, [["id": "sess-9", "client_id": "me", "trainer_id": "coach", "status": "live"]] as [[String: Any]]),
            (500, ["message": "boom"] as [String: Any]),        // pushSet fails
            (200, [["id": "sess-9", "client_id": "me", "trainer_id": "coach", "status": "abandoned"]] as [[String: Any]]),
        ]
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db)

        await #expect(throws: SharingError.self) {
            try await svc.shareCompletedWorkout(to: "coach", workoutName: "Push Day", sets: [
                .init(exerciseName: "Bench Press", exerciseOrder: 0, setOrder: 1,
                      weightLbs: 135, reps: 10, isWarmup: false),
            ])
        }
        // start + failed push + best-effort abandon PATCH — the session must
        // not be left status=live forever in the friend's feed.
        #expect(mock.requests.count == 3)
        #expect(mock.requests.last?.httpMethod == "PATCH")
        #expect(mock.lastBody?["status"] as? String == "abandoned")
    }

    // MARK: Token refresh

    @Test func deadRefreshTokenClearsSessionForRecovery() async throws {
        let mock = MockHTTP()
        mock.queue = [(403, ["msg": "invalid refresh token"] as [String: Any])]  // refresh rejected
        let (svc, db) = try makeService(mock)
        SharingSessionStore.save(
            .init(userID: "gone", username: "ghost", accessToken: "OLD",
                  refreshToken: "DEAD", expiresAt: Date().addingTimeInterval(-10)), db: db)

        await #expect(throws: SharingError.notSignedIn) { _ = try await svc.searchUsers("x") }
        // The stale session is wiped so the UI can recover to the picker.
        #expect(!SharingSessionStore.isSignedIn(db: db))
    }

    @Test func validateSessionFalseWhenProfileWiped() async throws {
        let mock = MockHTTP()
        mock.queue = [(200, [[String: Any]]())]   // profiles?id=eq.me -> [] (account wiped)
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db, username: "ashish")   // valid, non-expired token

        let ok = await svc.validateSession()
        #expect(!ok)
        #expect(!SharingSessionStore.isSignedIn(db: db))
    }

    @Test func validateSessionTrueWhenProfileExists() async throws {
        let mock = MockHTTP()
        mock.queue = [(200, [["id": "me", "username": "ashish"]] as [[String: Any]])]
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db, username: "ashish")
        #expect(await svc.validateSession())
        #expect(SharingSessionStore.isSignedIn(db: db))
    }

    @Test func expiredTokenTriggersRefresh() async throws {
        let mock = MockHTTP()
        // 1) refresh response, 2) the actual search response.
        mock.queue = [
            (200, ["access_token": "AT-2", "refresh_token": "RT-2", "expires_in": 3600,
                   "user": ["id": "me"]] as [String: Any]),
            (200, [[String: Any]]()),
        ]
        let (svc, db) = try makeService(mock)
        // Signed in but already expired.
        SharingSessionStore.save(
            .init(userID: "me", username: "me", accessToken: "OLD",
                  refreshToken: "RT", expiresAt: Date().addingTimeInterval(-10)),
            db: db)

        _ = try await svc.searchUsers("x")
        // First call was the token refresh; the search then used the new token.
        #expect(mock.requests.first?.url?.absoluteString.contains("grant_type=refresh_token") == true)
        #expect(mock.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer AT-2")
        #expect(SharingSessionStore.load(db: db)?.accessToken == "AT-2")
    }

    // MARK: Managing existing connections

    private func edge(_ id: String, _ from: String, _ to: String,
                      role: String = "friend") -> [String: Any] {
        ["id": id, "requester_id": from, "addressee_id": to,
         "status": "accepted", "role": role]
    }

    /// Promotion is a REQUEST (operator decision 2026-07-29): one pending
    /// trainer edge, the friend edge untouched — never a PATCH, never an
    /// already-accepted insert, whoever initiated the friendship.
    @Test func promotionSendsAPendingTrainerRequestAndTouchesNothingElse() async throws {
        let mock = MockHTTP()
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db)
        // Two responses: the connection-ceiling read, then the insert. The read
        // was added 2026-07-30 (SharingService.maxConnections).
        mock.queue = [(200, [Any]()), (201, [Any]())]

        try await svc.requestCoachPromotion("hud")
        // The invariant is about WRITES, not call count: exactly one, and it's
        // an insert of a new edge. A GET is free; a PATCH would rewrite the
        // friendship out from under both people.
        let writes = mock.requests.filter { $0.httpMethod != "GET" }
        #expect(writes.count == 1, "one write only — the friend edge is never modified")
        #expect(!mock.requests.contains { $0.httpMethod == "PATCH" || $0.httpMethod == "DELETE" })
        let last = mock.requests.last
        #expect(last?.httpMethod == "POST")
        #expect(last?.url?.absoluteString.hasSuffix("friendships") == true)
        #expect(mock.lastBody?["role"] as? String == "trainer")
        #expect(mock.lastBody?["requester_id"] as? String == "me")
        // No status in the body — the row is born 'pending' server-side and
        // goes through the same accept flow as every other request.
        #expect(mock.lastBody?["status"] == nil)
    }

    /// Demoting a coach with a friendship underneath deletes the trainer edge
    /// (and only it) — the friendship survives.
    @Test func demoteDeletesTrainerEdgeWhenFriendshipRemains() async throws {
        let mock = MockHTTP()
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db)
        mock.queue = [(200, [edge("e1", "hud", "me"),
                             edge("e2", "me", "hud", role: "trainer")]),
                      (204, [Any]()), (204, [Any]())]

        try await svc.demoteCoach("hud")
        let urls = mock.requests.compactMap { $0.url?.absoluteString }
        #expect(urls.contains { $0.contains("friendships?id=eq.e2") })
        #expect(!urls.contains { $0.contains("friendships?id=eq.e1") },
                "the friend edge must survive a demotion")
    }

    /// Unfriending deletes EVERY edge with the person, and a coach edge takes
    /// the briefing down with it.
    @Test func removeConnectionDeletesAllEdgesAndRevokesBriefing() async throws {
        let mock = MockHTTP()
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db)
        mock.queue = [(200, [edge("e1", "hud", "me"),
                             edge("e2", "me", "hud", role: "trainer")]),
                      (204, [Any]()), (204, [Any]()), (204, [Any]())]

        try await svc.removeConnection(with: "hud")
        let urls = mock.requests.compactMap { $0.url?.absoluteString }
        #expect(urls.contains { $0.contains("friendships?id=eq.e1") })
        #expect(urls.contains { $0.contains("friendships?id=eq.e2") })
        #expect(urls.contains { $0.contains("client_briefings?client_id=eq.me&coach_id=eq.hud") })
    }

    /// After a promotion the person carries two edges — the hub must show ONE
    /// row, and it must be the coach one.
    @Test func connectionsDedupePrefersCoachOverFriend() async throws {
        let mock = MockHTTP()
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db)
        mock.queue = [(200, [edge("e1", "hud", "me"),
                             edge("e2", "me", "hud", role: "trainer")]),
                      (200, [["id": "hud", "username": "hudson"]])]

        let conns = try await svc.connections()
        #expect(conns.count == 1)
        #expect(conns.first?.kind == .coach)
        #expect(conns.first?.profile.username == "hudson")
    }

    // MARK: Global boards (#1170)

    /// THE REGRESSION. The worldwide queries must ask for BOTH period keys.
    ///
    /// This is the assertion the pure ranking tests cannot make: the rows were
    /// selected correctly, the query just never asked for them. `period_start`
    /// was pinned with `eq.` to the current key, so at every Monday rollover the
    /// global board went blank while the friends board — which already used
    /// `in.(…)` — kept listing the same people.
    @Test func theWorldwidePodiumAsksForBothPeriodKeys() async throws {
        let mock = MockHTTP()
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db)

        _ = try await svc.globalPodium(boardKey: "steps",
                                       periods: ["2026-08-03", "2026-07-27"])
        let url = try #require(mock.requests.last?.url?.absoluteString.removingPercentEncoding)
        #expect(url.contains("2026-08-03"), "the current key")
        #expect(url.contains("2026-07-27"), "and the one before it — the whole bug")
        #expect(!url.contains("period_start=eq."), "a single pinned key is the defect")
    }

    @Test func theWorldwideBracketAsksForBothPeriodKeys() async throws {
        let mock = MockHTTP()
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db)

        _ = try await svc.globalBracket(boardKey: "steps",
                                        periods: ["2026-08-03", "2026-07-27"],
                                        around: 40_000)
        let urls = mock.requests.compactMap { $0.url?.absoluteString.removingPercentEncoding }
        // Both halves of the bracket — the rows above you and the ones below.
        #expect(urls.filter { $0.contains("2026-07-27") && $0.contains("2026-08-03") }.count == 2)
        #expect(!urls.contains { $0.contains("period_start=eq.") })
    }

    /// Only rows their owner opened to Everyone may appear worldwide. A missing
    /// `visibility` filter would turn a ranking into a leak.
    @Test func worldwideQueriesStayScopedToGloballyPublishedRows() async throws {
        let mock = MockHTTP()
        let (svc, db) = try makeService(mock)
        signIn(svc, db: db)

        _ = try await svc.globalPodium(boardKey: "steps", periods: ["2026-08-03"])
        let url = try #require(mock.requests.last?.url?.absoluteString)
        #expect(url.contains("visibility=eq.global"))
    }
}
