import Foundation
import GRDB
import Testing
@testable import DriftCore

/// Tier-0: the sharing foundation's countable behavior — DTO wire mapping,
/// the durable session store, and the local↔server ID bridge. No network; the
/// SyncClient/SharingService HTTP layer is exercised separately.
@MainActor
struct SharingFoundationTests {

    // MARK: DTO wire mapping (snake_case ⇄ Codable)

    @Test func profileDecodesSnakeCase() throws {
        let json = #"{"id":"u1","username":"ash","display_name":"Ash","avatar_url":null}"#
        let p = try SharingJSON.decoder.decode(SharedProfile.self, from: Data(json.utf8))
        #expect(p.id == "u1")
        #expect(p.username == "ash")
        #expect(p.displayName == "Ash")
        #expect(p.avatarUrl == nil)
    }

    @Test func sharedTemplateDecodesEmbeddedExercises() throws {
        let exercises = #"[{\"name\":\"Bench Press\",\"sets\":3},{\"name\":\"Squat\",\"sets\":5}]"#
        let json = """
        {"id":"t1","owner_id":"o1","recipient_id":"r1","name":"Push Day",
         "exercises_json":"\(exercises)","note":"go heavy","status":"sent"}
        """
        let dto = try SharingJSON.decoder.decode(SharedTemplateDTO.self, from: Data(json.utf8))
        #expect(dto.name == "Push Day")
        #expect(dto.status == .sent)
        #expect(dto.exercises.count == 2)
        #expect(dto.exercises.first?.name == "Bench Press")
    }

    @Test func liveWorkoutSetRoundTrips() throws {
        let json = """
        {"id":"s1","live_workout_id":"w1","exercise_name":"Deadlift","exercise_order":0,
         "set_order":1,"weight_lbs":225.0,"reps":5,"is_warmup":false,"done":true}
        """
        let dto = try SharingJSON.decoder.decode(LiveWorkoutSetDTO.self, from: Data(json.utf8))
        #expect(dto.exerciseName == "Deadlift")
        #expect(dto.weightLbs == 225.0)
        #expect(dto.reps == 5)
        #expect(dto.done)
        // Encodes back to snake_case keys.
        let out = try SharingJSON.encoder.encode(dto)
        let s = String(decoding: out, as: UTF8.self)
        #expect(s.contains("\"live_workout_id\""))
        #expect(s.contains("\"is_warmup\""))
    }

    // MARK: Durable session store (sync_session)

    @Test func sessionSaveLoadClear() throws {
        let db = try AppDatabase.empty()
        #expect(!SharingSessionStore.isSignedIn(db: db))

        let expires = Date(timeIntervalSince1970: 2_000_000_000)
        let session = SharingSession(userID: "uid-1", username: "ash",
                                     accessToken: "tok", refreshToken: "ref",
                                     expiresAt: expires)
        SharingSessionStore.save(session, db: db)

        let loaded = SharingSessionStore.load(db: db)
        #expect(loaded?.userID == "uid-1")
        #expect(loaded?.username == "ash")
        #expect(loaded?.accessToken == "tok")
        #expect(loaded?.refreshToken == "ref")
        #expect(loaded?.expiresAt == expires)
        #expect(SharingSessionStore.isSignedIn(db: db))

        SharingSessionStore.clear(db: db)
        #expect(!SharingSessionStore.isSignedIn(db: db))
        #expect(SharingSessionStore.load(db: db) == nil)
    }

    @Test func sessionSaveIsSingleRowUpsert() throws {
        let db = try AppDatabase.empty()
        SharingSessionStore.save(.init(userID: "a", username: "one",
                                       accessToken: "t1", refreshToken: nil, expiresAt: nil), db: db)
        SharingSessionStore.save(.init(userID: "a", username: "two",
                                       accessToken: "t2", refreshToken: nil, expiresAt: nil), db: db)
        let rows = try db.reader.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM sync_session") ?? 0
        }
        #expect(rows == 1)
        #expect(SharingSessionStore.load(db: db)?.username == "two")
    }

    @Test func sessionExpiryDetection() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let live = SharingSession(userID: "a", username: nil, accessToken: "t",
                                  refreshToken: nil, expiresAt: now.addingTimeInterval(3600))
        let dead = SharingSession(userID: "a", username: nil, accessToken: "t",
                                  refreshToken: nil, expiresAt: now.addingTimeInterval(30))
        #expect(!live.isExpired(now: now))
        #expect(dead.isExpired(now: now), "within 60s skew counts as expired")
    }

    // MARK: Local↔server ID bridge (sync_map)

    @Test func syncMapLinksAndResolvesBothWays() throws {
        let db = try AppDatabase.empty()
        #expect(SyncMap.serverUUID(.template, localID: 7, db: db) == nil)

        SyncMap.link(.template, localID: 7, serverUUID: "uuid-abc", db: db)
        #expect(SyncMap.serverUUID(.template, localID: 7, db: db) == "uuid-abc")
        #expect(SyncMap.localID(.template, serverUUID: "uuid-abc", db: db) == 7)

        // Re-link updates the mapping, doesn't duplicate.
        SyncMap.link(.template, localID: 7, serverUUID: "uuid-xyz", db: db)
        #expect(SyncMap.serverUUID(.template, localID: 7, db: db) == "uuid-xyz")
        let rows = try db.reader.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM sync_map") ?? 0
        }
        #expect(rows == 1)
    }

    @Test func syncMapKeysByEntityType() throws {
        let db = try AppDatabase.empty()
        SyncMap.link(.template, localID: 1, serverUUID: "t-uuid", db: db)
        SyncMap.link(.workout, localID: 1, serverUUID: "w-uuid", db: db)
        #expect(SyncMap.serverUUID(.template, localID: 1, db: db) == "t-uuid")
        #expect(SyncMap.serverUUID(.workout, localID: 1, db: db) == "w-uuid")
    }
}
