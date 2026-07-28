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

    // MARK: Token refresh

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
}
