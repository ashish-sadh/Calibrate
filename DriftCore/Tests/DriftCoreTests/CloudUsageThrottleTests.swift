import Foundation
import GRDB
import Testing
@testable import DriftCore

/// Tier-0: the per-device daily cloud budget (#1113). The gate itself is six
/// lines in RemoteLLMBackend (and bypassed under XCTest so evals never trip
/// it); the countable behavior — caps, rollover, prune, fail-open — lives
/// here against an in-memory DB.
struct CloudUsageThrottleTests {

    private func day(_ s: String) -> Date {
        DateFormatters.dateOnly.date(from: s)!
    }

    @Test func requestCapTrips() throws {
        let db = try AppDatabase.empty()
        let now = day("2026-07-27")
        for _ in 0..<CloudUsageThrottle.maxRequestsPerDay {
            #expect(CloudUsageThrottle.permit(estimatedChars: 10, db: db, now: now))
        }
        #expect(!CloudUsageThrottle.permit(estimatedChars: 10, db: db, now: now),
                "request \(CloudUsageThrottle.maxRequestsPerDay + 1) must be denied")
    }

    @Test func charBudgetTrips() throws {
        let db = try AppDatabase.empty()
        let now = day("2026-07-27")
        // Two huge turns fit; the third crosses maxCharsPerDay.
        let big = CloudUsageThrottle.maxCharsPerDay / 2 - 100
        #expect(CloudUsageThrottle.permit(estimatedChars: big, db: db, now: now))
        #expect(CloudUsageThrottle.permit(estimatedChars: big, db: db, now: now))
        #expect(!CloudUsageThrottle.permit(estimatedChars: big, db: db, now: now))
        // A tiny call still fits in the remaining slack.
        #expect(CloudUsageThrottle.permit(estimatedChars: 50, db: db, now: now))
    }

    @Test func dayRolloverResetsBudget() throws {
        let db = try AppDatabase.empty()
        let yesterday = day("2026-07-27")
        for _ in 0..<CloudUsageThrottle.maxRequestsPerDay {
            CloudUsageThrottle.permit(estimatedChars: 10, db: db, now: yesterday)
        }
        #expect(!CloudUsageThrottle.permit(estimatedChars: 10, db: db, now: yesterday))

        let today = day("2026-07-28")
        #expect(CloudUsageThrottle.permit(estimatedChars: 10, db: db, now: today),
                "new local day = fresh budget")
        // Rollover pruned yesterday's row — the table never grows.
        let rows = try db.reader.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM cloud_usage") ?? 0
        }
        #expect(rows == 1)
    }

    @Test func recordAddsReplyCharsAndRemainingReflectsBoth() throws {
        let db = try AppDatabase.empty()
        let now = day("2026-07-27")
        CloudUsageThrottle.permit(estimatedChars: 1_000, db: db, now: now)
        CloudUsageThrottle.record(chars: 2_000, db: db, now: now)
        let remaining = CloudUsageThrottle.remainingToday(db: db, now: now)
        #expect(remaining.requests == CloudUsageThrottle.maxRequestsPerDay - 1)
        #expect(remaining.chars == CloudUsageThrottle.maxCharsPerDay - 3_000)
    }
}
