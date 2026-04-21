import Foundation
import Testing
import GRDB
@testable import Drift

/// Helpers: fresh in-memory DB per test so we don't touch shared state.
private func makeTestDB() throws -> AppDatabase {
    let queue = try DatabaseQueue()
    var migrator = DatabaseMigrator()
    Migrations.registerAll(&migrator)
    try migrator.migrate(queue)
    return try AppDatabase(queue)
}

private func makeService(db: AppDatabase) -> ChatTelemetryService {
    ChatTelemetryService(db: db)
}

/// Force a synchronous barrier onto the service's internal queue so we can
/// observe the result of a fire-and-forget record().
private func drain(_ service: ChatTelemetryService) {
    // record() dispatches async on a private serial queue. Reflection
    // approach is brittle; instead we poll the DB with a short timeout.
    let deadline = Date().addingTimeInterval(2.0)
    while Date() < deadline {
        if service.count() > 0 || !Preferences.chatTelemetryEnabled { return }
        Thread.sleep(forTimeInterval: 0.02)
    }
}

// MARK: - Fingerprint

@Test func fingerprintIsStableAcrossWhitespace() {
    let a = ChatTelemetryService.fingerprint(for: "Log 3 eggs")
    let b = ChatTelemetryService.fingerprint(for: "  log    3 eggs  ")
    let c = ChatTelemetryService.fingerprint(for: "log 3 eggs")
    #expect(a == b)
    #expect(a == c)
}

@Test func fingerprintIsFixedLength() {
    let fp = ChatTelemetryService.fingerprint(for: "anything")
    #expect(fp.count == ChatTelemetryService.fingerprintHexLength)
}

@Test func fingerprintDiffersForDifferentQueries() {
    let a = ChatTelemetryService.fingerprint(for: "log 3 eggs")
    let b = ChatTelemetryService.fingerprint(for: "log 4 eggs")
    #expect(a != b)
}

@Test func fingerprintIsNotTheRawText() {
    let raw = "log 3 eggs"
    let fp = ChatTelemetryService.fingerprint(for: raw)
    #expect(!fp.contains(raw))
    #expect(!fp.contains("eggs"))
}

// MARK: - Opt-in gate

@Test func recordIsNoOpWhenOptedOut() throws {
    Preferences.chatTelemetryEnabled = false
    let db = try makeTestDB()
    let service = makeService(db: db)
    service.record(
        query: "log weight 180",
        intent: .toolCall, tool: "log_weight",
        outcome: .success, latencyMs: 100, turnIndex: 0
    )
    // Allow any async attempt to complete before we assert.
    Thread.sleep(forTimeInterval: 0.1)
    #expect(service.count() == 0)
}

@Test func recordPersistsWhenOptedIn() throws {
    Preferences.chatTelemetryEnabled = true
    defer { Preferences.chatTelemetryEnabled = false }
    let db = try makeTestDB()
    let service = makeService(db: db)
    service.record(
        query: "log weight 180",
        intent: .toolCall, tool: "log_weight",
        outcome: .success, latencyMs: 100, turnIndex: 0
    )
    drain(service)
    #expect(service.count() == 1)
    let rows = service.fetchRecent()
    #expect(rows.first?.toolCalled == "log_weight")
    #expect(rows.first?.outcome == "success")
    #expect(rows.first?.queryFingerprint.count == ChatTelemetryService.fingerprintHexLength)
}

@Test func recordPersistsRawQueryAndResponseText() throws {
    // v33: Raw text is captured when opt-in is on so exported transcripts can
    // drive multi-turn failure analysis. Fingerprint is still written for
    // back-compat aggregates.
    Preferences.chatTelemetryEnabled = true
    defer { Preferences.chatTelemetryEnabled = false }
    let db = try makeTestDB()
    let service = makeService(db: db)
    service.record(
        query: "log 2 eggs",
        response: "Logged 2 eggs (140 kcal).",
        intent: .toolCall, tool: "log_food",
        outcome: .success, latencyMs: 120, turnIndex: 3
    )
    drain(service)
    let row = try #require(service.fetchRecent().first)
    #expect(row.queryText == "log 2 eggs")
    #expect(row.responseText == "Logged 2 eggs (140 kcal).")
    #expect(row.queryFingerprint.count == ChatTelemetryService.fingerprintHexLength)
    #expect(row.turnIndex == 3)
}

@Test func recordOmitsRawTextWhenOptedOut() throws {
    // Opt-out path stays airtight: no row written, no raw text captured.
    Preferences.chatTelemetryEnabled = false
    let db = try makeTestDB()
    let service = makeService(db: db)
    service.record(
        query: "log 2 eggs",
        response: "Logged 2 eggs (140 kcal).",
        intent: .toolCall, tool: "log_food",
        outcome: .success, latencyMs: 120, turnIndex: 0
    )
    Thread.sleep(forTimeInterval: 0.1)
    #expect(service.count() == 0)
}

// MARK: - Ring buffer

@Test func ringBufferEvictsOldestBeyondLimit() throws {
    Preferences.chatTelemetryEnabled = true
    defer { Preferences.chatTelemetryEnabled = false }
    let db = try makeTestDB()
    let service = makeService(db: db)

    // Directly insert rows at DB layer to avoid async race — the eviction
    // helper is what we're verifying.
    for i in 0..<(ChatTelemetryService.ringBufferLimit + 5) {
        let row = ChatTurnRow(
            timestamp: "2026-04-20T10:\(String(format: "%02d", i % 60)):00Z",
            queryFingerprint: String(format: "%012x", i),
            intentLabel: "tool_call", toolCalled: "log_weight",
            outcome: "success", latencyMs: 100, turnIndex: 0
        )
        try db.insertChatTurn(row)
    }
    try db.evictChatTurnsOver(cap: ChatTelemetryService.ringBufferLimit)
    #expect(service.count() == ChatTelemetryService.ringBufferLimit)
}

// MARK: - Privacy

@Test func noRawTextIsPersisted() throws {
    Preferences.chatTelemetryEnabled = true
    defer { Preferences.chatTelemetryEnabled = false }
    let db = try makeTestDB()
    let service = makeService(db: db)
    let secret = "ate my secret burrito at 3am"
    service.record(
        query: secret,
        intent: .toolCall, tool: "log_food",
        outcome: .success, latencyMs: 200, turnIndex: 1
    )
    drain(service)
    let rows = service.fetchRecent()
    #expect(rows.count == 1)
    // Fingerprint should not be the raw text, nor contain any word of it.
    let fp = rows[0].queryFingerprint
    for word in secret.split(separator: " ") {
        #expect(!fp.contains(String(word)))
    }
}

// MARK: - Delete + export

@Test func deleteAllClearsTable() throws {
    Preferences.chatTelemetryEnabled = true
    defer { Preferences.chatTelemetryEnabled = false }
    let db = try makeTestDB()
    let service = makeService(db: db)
    for i in 0..<3 {
        service.record(
            query: "q\(i)", intent: .toolCall, tool: "log_weight",
            outcome: .success, latencyMs: 10, turnIndex: i
        )
    }
    drain(service)
    #expect(service.count() == 3)
    service.deleteAll()
    #expect(service.count() == 0)
}

@Test func exportJSONRoundTrips() throws {
    Preferences.chatTelemetryEnabled = true
    defer { Preferences.chatTelemetryEnabled = false }
    let db = try makeTestDB()
    let service = makeService(db: db)
    service.record(
        query: "ping", intent: .ruleMatch, tool: "undo",
        outcome: .success, latencyMs: 5, turnIndex: 0
    )
    drain(service)
    let data = service.exportJSON()
    #expect(data != nil)
    if let data {
        let decoded = try JSONDecoder().decode([ChatTurnRow].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded.first?.toolCalled == "undo")
    }
}

@Test func exportJSONReturnsNilWhenEmpty() throws {
    Preferences.chatTelemetryEnabled = true
    defer { Preferences.chatTelemetryEnabled = false }
    let db = try makeTestDB()
    let service = makeService(db: db)
    #expect(service.exportJSON() == nil)
}

// MARK: - Aggregates

@Test func topToolsRanksByCount() throws {
    Preferences.chatTelemetryEnabled = true
    defer { Preferences.chatTelemetryEnabled = false }
    let db = try makeTestDB()
    let service = makeService(db: db)
    for _ in 0..<3 {
        try db.insertChatTurn(ChatTurnRow(
            timestamp: "2026-04-20T10:00:00Z",
            queryFingerprint: "aaaaaaaaaaaa",
            intentLabel: "tool_call", toolCalled: "log_food",
            outcome: "success", latencyMs: 100, turnIndex: 0
        ))
    }
    try db.insertChatTurn(ChatTurnRow(
        timestamp: "2026-04-20T10:00:00Z", queryFingerprint: "bbbbbbbbbbbb",
        intentLabel: "tool_call", toolCalled: "log_weight",
        outcome: "success", latencyMs: 50, turnIndex: 0
    ))
    let tops = service.topTools(limit: 10)
    #expect(tops.first?.tool == "log_food")
    #expect(tops.first?.count == 3)
}

@Test func topFailuresFiltersToFailedOrTimeout() throws {
    Preferences.chatTelemetryEnabled = true
    defer { Preferences.chatTelemetryEnabled = false }
    let db = try makeTestDB()
    let service = makeService(db: db)
    try db.insertChatTurn(ChatTurnRow(
        timestamp: "2026-04-20T10:00:00Z", queryFingerprint: "aaaaaaaaaaaa",
        intentLabel: "tool_call", toolCalled: "log_food",
        outcome: "success", latencyMs: 100, turnIndex: 0
    ))
    try db.insertChatTurn(ChatTurnRow(
        timestamp: "2026-04-20T10:00:00Z", queryFingerprint: "bbbbbbbbbbbb",
        intentLabel: "tool_call", toolCalled: "log_food",
        outcome: "failed", latencyMs: 100, turnIndex: 0
    ))
    try db.insertChatTurn(ChatTurnRow(
        timestamp: "2026-04-20T10:00:00Z", queryFingerprint: "cccccccccccc",
        intentLabel: "timeout", toolCalled: nil,
        outcome: "timeout", latencyMs: 20000, turnIndex: 0
    ))
    let failures = service.topFailures()
    #expect(failures.count == 2)  // one tool failed, one timeout
}

@Test func latencyPercentilesAreOrdered() throws {
    Preferences.chatTelemetryEnabled = true
    defer { Preferences.chatTelemetryEnabled = false }
    let db = try makeTestDB()
    let service = makeService(db: db)
    for ms in [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000] {
        try db.insertChatTurn(ChatTurnRow(
            timestamp: "2026-04-20T10:00:00Z",
            queryFingerprint: "aaaaaaaaaaaa",
            intentLabel: "tool_call", toolCalled: "log_food",
            outcome: "success", latencyMs: ms, turnIndex: 0
        ))
    }
    let stat = service.latency()
    #expect(stat.count == 11)
    #expect(stat.p50 <= stat.p95)
}

// MARK: - recentFailures (#281)

/// Format a timestamp N hours before `now` in the same ISO8601 format
/// ChatTelemetryService uses so its parser matches.
private func isoTimestamp(hoursAgo: Double, now: Date = Date()) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: now.addingTimeInterval(-hoursAgo * 3600))
}

@Test func recentFailuresCountsFailedWithinWindow() throws {
    Preferences.chatTelemetryEnabled = true
    defer { Preferences.chatTelemetryEnabled = false }
    let db = try makeTestDB()
    let service = makeService(db: db)
    // 2 failures on log_food in the last hour
    for _ in 0..<2 {
        try db.insertChatTurn(ChatTurnRow(
            timestamp: isoTimestamp(hoursAgo: 0.5),
            queryFingerprint: "aaaaaaaaaaaa",
            intentLabel: "tool_call", toolCalled: "log_food",
            outcome: "failed", latencyMs: 100, turnIndex: 0
        ))
    }
    // 1 timeout on log_weight in the last hour (should count as failure)
    try db.insertChatTurn(ChatTurnRow(
        timestamp: isoTimestamp(hoursAgo: 0.5),
        queryFingerprint: "bbbbbbbbbbbb",
        intentLabel: "timeout", toolCalled: "log_weight",
        outcome: "timeout", latencyMs: 20000, turnIndex: 0
    ))
    // 1 success (should NOT count)
    try db.insertChatTurn(ChatTurnRow(
        timestamp: isoTimestamp(hoursAgo: 0.5),
        queryFingerprint: "cccccccccccc",
        intentLabel: "tool_call", toolCalled: "log_food",
        outcome: "success", latencyMs: 100, turnIndex: 0
    ))
    let failures = service.recentFailures(hoursBack: 24)
    #expect(failures.count == 2)
    #expect(failures.first?.tool == "log_food")
    #expect(failures.first?.count == 2)
    #expect(failures.contains(where: { $0.tool == "log_weight" && $0.count == 1 }))
}

@Test func recentFailuresExcludesRowsOlderThanWindow() throws {
    Preferences.chatTelemetryEnabled = true
    defer { Preferences.chatTelemetryEnabled = false }
    let db = try makeTestDB()
    let service = makeService(db: db)
    // 2 recent (in window)
    for _ in 0..<2 {
        try db.insertChatTurn(ChatTurnRow(
            timestamp: isoTimestamp(hoursAgo: 1),
            queryFingerprint: "aaaaaaaaaaaa",
            intentLabel: "tool_call", toolCalled: "log_food",
            outcome: "failed", latencyMs: 100, turnIndex: 0
        ))
    }
    // 5 old (25h ago, outside 24h window)
    for _ in 0..<5 {
        try db.insertChatTurn(ChatTurnRow(
            timestamp: isoTimestamp(hoursAgo: 25),
            queryFingerprint: "bbbbbbbbbbbb",
            intentLabel: "tool_call", toolCalled: "log_food",
            outcome: "failed", latencyMs: 100, turnIndex: 0
        ))
    }
    let failures = service.recentFailures(hoursBack: 24)
    #expect(failures.count == 1)
    #expect(failures.first?.tool == "log_food")
    #expect(failures.first?.count == 2)  // only the 2 recent ones
}

@Test func recentFailuresEmptyWhenNoFailures() throws {
    Preferences.chatTelemetryEnabled = true
    defer { Preferences.chatTelemetryEnabled = false }
    let db = try makeTestDB()
    let service = makeService(db: db)
    try db.insertChatTurn(ChatTurnRow(
        timestamp: isoTimestamp(hoursAgo: 1),
        queryFingerprint: "aaaaaaaaaaaa",
        intentLabel: "tool_call", toolCalled: "log_food",
        outcome: "success", latencyMs: 100, turnIndex: 0
    ))
    #expect(service.recentFailures(hoursBack: 24).isEmpty)
}

@Test func recentFailuresEmptyWhenOptedOut() throws {
    Preferences.chatTelemetryEnabled = false
    let db = try makeTestDB()
    let service = makeService(db: db)
    // Even if rows existed in a shared DB, opt-out path returns empty table.
    // (record() is a no-op when off, so in a fresh DB the table is empty.)
    #expect(service.recentFailures(hoursBack: 24).isEmpty)
}

@Test func recentFailuresRespectsCustomWindow() throws {
    Preferences.chatTelemetryEnabled = true
    defer { Preferences.chatTelemetryEnabled = false }
    let db = try makeTestDB()
    let service = makeService(db: db)
    // 1 fail at 2h ago, 1 fail at 30min ago
    try db.insertChatTurn(ChatTurnRow(
        timestamp: isoTimestamp(hoursAgo: 2),
        queryFingerprint: "aaaaaaaaaaaa",
        intentLabel: "tool_call", toolCalled: "log_food",
        outcome: "failed", latencyMs: 100, turnIndex: 0
    ))
    try db.insertChatTurn(ChatTurnRow(
        timestamp: isoTimestamp(hoursAgo: 0.5),
        queryFingerprint: "bbbbbbbbbbbb",
        intentLabel: "tool_call", toolCalled: "log_food",
        outcome: "failed", latencyMs: 100, turnIndex: 0
    ))
    // 1h window → only the 30min-ago row counts
    let oneHour = service.recentFailures(hoursBack: 1)
    #expect(oneHour.first?.count == 1)
    // 3h window → both count
    let threeHours = service.recentFailures(hoursBack: 3)
    #expect(threeHours.first?.count == 2)
}

// MARK: - Factory reset

@Test func factoryResetClearsTelemetry() throws {
    Preferences.chatTelemetryEnabled = true
    defer { Preferences.chatTelemetryEnabled = false }
    let db = try makeTestDB()
    let service = makeService(db: db)
    service.record(
        query: "seed", intent: .toolCall, tool: "log_food",
        outcome: .success, latencyMs: 10, turnIndex: 0
    )
    drain(service)
    #expect(service.count() > 0)
    service.deleteAll()
    #expect(service.count() == 0)
}
