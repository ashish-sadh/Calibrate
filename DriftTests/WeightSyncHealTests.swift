import Foundation
@testable import Drift
import Testing

// MARK: - Weight sync self-heal (field report 2026-07-10)
// An anchored HK sync that returns 0 while Apple Health holds weight days we
// don't have locally means the anchor is stale/poisoned. These pin the pure
// decision; the HK query plumbing is device-only.

@Test func unsyncedDayDetectedWhenHKHasUnknownDate() {
    let hasUnsynced = HealthKitService.hasUnsyncedDay(
        hkDays: ["2026-07-08", "2026-07-09"],
        localDates: ["2026-07-08"])
    #expect(hasUnsynced, "2026-07-09 exists in HK but not locally → heal")
}

@Test func noHealWhenAllHKDaysKnown() {
    let hasUnsynced = HealthKitService.hasUnsyncedDay(
        hkDays: ["2026-07-08", "2026-07-09"],
        localDates: ["2026-07-07", "2026-07-08", "2026-07-09"])
    #expect(!hasUnsynced, "everything HK has is already local → no resync churn")
}

@Test func noHealOnEmptyProbe() {
    // Read denied (or genuinely no data) → probe is empty → never heal-loop.
    #expect(!HealthKitService.hasUnsyncedDay(hkDays: [], localDates: []))
    #expect(!HealthKitService.hasUnsyncedDay(hkDays: [], localDates: ["2026-07-08"]))
}
