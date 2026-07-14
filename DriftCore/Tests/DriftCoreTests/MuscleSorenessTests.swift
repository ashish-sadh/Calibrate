import Testing
import Foundation
@testable import DriftCore

// Tier 0 — pure logic for the soreness check-in model (learned per-group
// recovery hours). Persistence (loadState/saveState) is a thin UserDefaults
// wrapper exercised implicitly by the view; everything here is pure.

// MARK: - Status thresholds

@Test func defaultEstimateReproducesLegacyDayThresholds() {
    // Old hardcoded coloring: day 0-1 recovering, day 2 moderate, day 3+
    // recovered. The 72h default must match it at day granularity.
    let h = MuscleSoreness.defaultRecoveryHours
    #expect(MuscleSoreness.status(hoursSince: 0, recoveryHours: h) == .recovering)
    #expect(MuscleSoreness.status(hoursSince: 24, recoveryHours: h) == .recovering)
    #expect(MuscleSoreness.status(hoursSince: 48, recoveryHours: h) == .moderate)
    #expect(MuscleSoreness.status(hoursSince: 72, recoveryHours: h) == .recovered)
    #expect(MuscleSoreness.status(hoursSince: 96, recoveryHours: h) == .recovered)
}

@Test func fasterLearnedRecoveryRecoversSooner() {
    // A user who reports "not sore" often ends up with a short estimate —
    // day 2 then reads recovered, not moderate.
    #expect(MuscleSoreness.status(hoursSince: 48, recoveryHours: 40) == .recovered)
    #expect(MuscleSoreness.status(hoursSince: 24, recoveryHours: 40) == .moderate)
}

// MARK: - Learning updates

@Test func stillSoreRaisesEstimate() {
    var state = MuscleSoreness.State()
    MuscleSoreness.applyResponse(group: "Legs", stillSore: true, hoursSince: 96,
                                 today: "2026-07-13", state: &state)
    let updated = MuscleSoreness.recoveryHours(for: "Legs", state: state)
    // target = 96 + 12 = 108; 72 + 0.35 × 36 = 84.6
    #expect(updated > 80 && updated < 90)
}

@Test func notSoreLowersEstimate() {
    var state = MuscleSoreness.State()
    MuscleSoreness.applyResponse(group: "Chest", stillSore: false, hoursSince: 48,
                                 today: "2026-07-13", state: &state)
    let updated = MuscleSoreness.recoveryHours(for: "Chest", state: state)
    // target = 48; 72 − 0.35 × 24 = 63.6
    #expect(updated > 60 && updated < 68)
}

@Test func consistentSoreAnswerBeforeEstimateIsNoOp() {
    // "Still sore" at 48h when the estimate is 72h is consistent with the
    // model (48 + 12 < 72) — no change.
    var state = MuscleSoreness.State()
    MuscleSoreness.applyResponse(group: "Back", stillSore: true, hoursSince: 48,
                                 today: "2026-07-13", state: &state)
    #expect(MuscleSoreness.recoveryHours(for: "Back", state: state) == 72)
}

@Test func repeatedNotSoreConvergesDownAndClamps() {
    var state = MuscleSoreness.State()
    for day in 0..<30 {
        MuscleSoreness.applyResponse(group: "Arms", stillSore: false, hoursSince: 24,
                                     today: "2026-06-\(String(format: "%02d", day % 28 + 1))",
                                     state: &state)
    }
    // Converges asymptotically toward the 24h floor (clamp only binds below).
    #expect(abs(MuscleSoreness.recoveryHours(for: "Arms", state: state) - MuscleSoreness.minRecoveryHours) < 0.1)
}

@Test func repeatedSoreConvergesUpAndClamps() {
    var state = MuscleSoreness.State()
    for day in 0..<40 {
        MuscleSoreness.applyResponse(group: "Legs", stillSore: true, hoursSince: 144,
                                     today: "2026-06-\(String(format: "%02d", day % 28 + 1))",
                                     state: &state)
    }
    #expect(MuscleSoreness.recoveryHours(for: "Legs", state: state) == MuscleSoreness.maxRecoveryHours)
}

// MARK: - Ask policy

@Test func asksInsideAmbiguityWindowOnly() {
    let state = MuscleSoreness.State()
    // 72h estimate → window is 36–108h. Day 2 (48h) qualifies.
    #expect(MuscleSoreness.questionCandidate(
        hoursSinceByGroup: ["Legs": 48], state: state, today: "2026-07-13") == "Legs")
    // Same-day training (0h) and long-recovered (120h) never ask.
    #expect(MuscleSoreness.questionCandidate(
        hoursSinceByGroup: ["Legs": 0], state: state, today: "2026-07-13") == nil)
    #expect(MuscleSoreness.questionCandidate(
        hoursSinceByGroup: ["Legs": 120], state: state, today: "2026-07-13") == nil)
}

@Test func oneQuestionPerDayGlobally() {
    var state = MuscleSoreness.State()
    MuscleSoreness.applyResponse(group: "Legs", stillSore: false, hoursSince: 48,
                                 today: "2026-07-13", state: &state)
    // Another group is in-window the same day — still silent.
    #expect(MuscleSoreness.questionCandidate(
        hoursSinceByGroup: ["Chest": 48], state: state, today: "2026-07-13") == nil)
    // Next day it may ask again.
    #expect(MuscleSoreness.questionCandidate(
        hoursSinceByGroup: ["Chest": 48], state: state, today: "2026-07-14") == "Chest")
}

@Test func sameGroupNotReaskedWithinThreeDays() {
    var state = MuscleSoreness.State()
    MuscleSoreness.markAsked(group: "Legs", today: "2026-07-13", state: &state)
    #expect(MuscleSoreness.questionCandidate(
        hoursSinceByGroup: ["Legs": 48], state: state, today: "2026-07-15") == nil)
    #expect(MuscleSoreness.questionCandidate(
        hoursSinceByGroup: ["Legs": 72], state: state, today: "2026-07-16") == "Legs")
}

@Test func picksGroupClosestToItsBoundary() {
    let state = MuscleSoreness.State()
    // Both in-window (36–108h); Chest at 72h sits ON its 72h boundary.
    let picked = MuscleSoreness.questionCandidate(
        hoursSinceByGroup: ["Legs": 48, "Chest": 72], state: state, today: "2026-07-13")
    #expect(picked == "Chest")
}

@Test func dismissSuppressesWithoutChangingEstimate() {
    var state = MuscleSoreness.State()
    MuscleSoreness.markAsked(group: "Core", today: "2026-07-13", state: &state)
    #expect(MuscleSoreness.recoveryHours(for: "Core", state: state) == MuscleSoreness.defaultRecoveryHours)
    #expect(MuscleSoreness.questionCandidate(
        hoursSinceByGroup: ["Core": 48], state: state, today: "2026-07-13") == nil)
}

// MARK: - State round-trip

@Test func stateCodableRoundTrips() throws {
    var state = MuscleSoreness.State()
    MuscleSoreness.applyResponse(group: "Legs", stillSore: true, hoursSince: 96,
                                 today: "2026-07-13", state: &state)
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(MuscleSoreness.State.self, from: data)
    #expect(decoded == state)
}
