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

// MARK: - Scale limits (2026-07-30)

/// These guard the seams where the social features stop being CORRECT rather
/// than merely slow. Every one of them was found by asking "what does this do at
/// 200 connections?" instead of by a failure report — which is the only time
/// it's cheap to fix.
struct SharingScaleTests {

    private func message(_ id: String, from sender: String, to me: String,
                         at when: Date) -> MessageDTO {
        MessageDTO(id: id, senderId: sender, recipientId: me, body: "hi",
                   createdAt: DateFormatters.iso8601.string(from: when))
    }

    /// A full window means correspondents fell off the end, so the unread
    /// numbers are a floor and the UI must not say "up to date".
    @Test func fullInboxWindowIsNotACompletePicture() {
        let now = Date()
        let messages = (0..<100).map { message("m\($0)", from: "peer\($0)", to: "me", at: now) }
        let rollup = Inbox.rollup(from: messages, me: "me", windowLimit: 100)
        #expect(!rollup.complete, "100 of 100 returned — there may be more")
    }

    @Test func partialInboxWindowIsComplete() {
        let messages = [message("m1", from: "peer1", to: "me", at: Date())]
        #expect(Inbox.rollup(from: messages, me: "me", windowLimit: 100).complete)
    }

    /// An empty inbox is genuinely empty, not "unknown" — otherwise a brand new
    /// user gets told to catch up on nothing.
    @Test func emptyInboxIsComplete() {
        let rollup = Inbox.rollup(from: [], me: "me", windowLimit: 100)
        #expect(rollup.complete)
        #expect(rollup.entries.isEmpty)
        #expect(rollup.totalUnread == 0)
    }

    /// The URL-length wall: `id=in.(…)` grows ~37 chars per UUID, and one
    /// oversized request would blank every friend row at once.
    @Test func profileFetchesStayInsideAnyProxyURLLimit() {
        let batch = SharingService.profileBatchSize
        let worstCaseURLBytes = batch * 37 + 64  // + the path and select clause
        #expect(worstCaseURLBytes < 8_192,
                "a single profiles chunk must fit a conservative 8 KB request line")
        // And the ceiling must actually need chunking, or the batching is dead code.
        #expect(SharingService.maxConnections > batch)
    }

    /// The ceiling has to sit below the point where the windows above stop
    /// covering everyone, or it isn't protecting anything.
    @Test func connectionCeilingSitsBelowTheWindowsItProtects() {
        #expect(SharingService.maxConnections <= SharingService.inboxWindow * 2,
                "past ~2 messages per connection the inbox window stops covering everyone")
    }
}
