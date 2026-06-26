import Foundation
@testable import DriftCore
import Testing

// MARK: - MedicationService Tests

@Test @MainActor func medicationServiceLogCreatesEntry() {
    let name = "TestMed_\(UUID().uuidString.prefix(8))"
    let result = MedicationService.logMedication(name: name, doseMg: 0.5, doseUnit: "mg")
    #expect(result.contains(name.capitalized))
    #expect(result.contains("0.5mg"))
}

@Test @MainActor func medicationServiceLogWithoutDose() {
    let name = "TestNoDose_\(UUID().uuidString.prefix(8))"
    let result = MedicationService.logMedication(name: name, doseMg: nil, doseUnit: nil)
    #expect(result.contains(name.capitalized))
    #expect(!result.contains("("))
}

@Test @MainActor func medicationServiceLogWholeDoseOmitsDecimal() {
    let result = MedicationService.logMedication(name: "Metformin", doseMg: 500, doseUnit: "mg")
    #expect(result.contains("500mg"), "Whole-number doses must not show decimal: got '\(result)'")
    #expect(!result.contains("500.0"))
}

@Test @MainActor func medicationServiceTodayMedicationsReturnsLogged() {
    let name = "TodayMed_\(UUID().uuidString.prefix(8))"
    _ = MedicationService.logMedication(name: name, doseMg: 1, doseUnit: "mg")
    let today = MedicationService.todayMedications()
    #expect(today.contains(where: { $0.name == name.capitalized }))
}

@Test @MainActor func medicationServiceMultipleLogsAccumulate() {
    // todayMedications() returns ALL of today's meds (global, unfiltered) and
    // Swift Testing runs Tier-0 in parallel — a concurrent med-logging test
    // inserting between the two snapshots makes a `+2` GLOBAL count-delta flake.
    // Assert both uniquely-named meds we logged are present instead (#906),
    // matching the DB-content-agnostic pattern in todayMedicationsReturnsLogged.
    let nameA = "DrugA_\(UUID().uuidString.prefix(8))"
    let nameB = "DrugB_\(UUID().uuidString.prefix(8))"
    _ = MedicationService.logMedication(name: nameA, doseMg: nil, doseUnit: nil)
    _ = MedicationService.logMedication(name: nameB, doseMg: nil, doseUnit: nil)
    let today = MedicationService.todayMedications()
    #expect(today.contains(where: { $0.name == nameA.capitalized }))
    #expect(today.contains(where: { $0.name == nameB.capitalized }))
}

@Test @MainActor func medicationServiceLogCapitalizesName() {
    let result = MedicationService.logMedication(name: "ozempic", doseMg: 0.5, doseUnit: "mg")
    #expect(result.contains("Ozempic"))
}

// MARK: - lastDoseTime

@Test @MainActor func lastDoseTimeReturnsNilForUnknownMedication() {
    let result = MedicationService.lastDoseTime(for: "NonExistentMed_\(UUID().uuidString)")
    #expect(result == nil)
}

@Test @MainActor func lastDoseTimeReturnsDateAfterLogging() {
    let name = "DoseTimeMed_\(UUID().uuidString.prefix(8))"
    let before = Date()
    _ = MedicationService.logMedication(name: name, doseMg: 1, doseUnit: "mg")
    let result = MedicationService.lastDoseTime(for: name)
    #expect(result != nil)
    #expect(result! >= before.addingTimeInterval(-1))
}

@Test @MainActor func lastDoseTimeReturnsLatestOfMultipleLogs() {
    let name = "MultiDoseMed_\(UUID().uuidString.prefix(8))"
    let before = Date()
    _ = MedicationService.logMedication(name: name, doseMg: 1, doseUnit: "mg")
    _ = MedicationService.logMedication(name: name, doseMg: 2, doseUnit: "mg")
    let result = MedicationService.lastDoseTime(for: name)
    #expect(result != nil)
    // ISO8601 storage truncates to second precision — allow 1s tolerance
    #expect(result!.timeIntervalSince(before) >= -1.0)
}

// MARK: - recentDoseHours

@Test @MainActor func recentDoseHoursReturnsEmptyForUnknownMedication() {
    let result = MedicationService.recentDoseHours(for: "Ghost_\(UUID().uuidString)")
    #expect(result.isEmpty)
}

@Test @MainActor func recentDoseHoursReturnsHourAfterLogging() {
    let name = "HourMed_\(UUID().uuidString.prefix(8))"
    _ = MedicationService.logMedication(name: name, doseMg: nil, doseUnit: nil)
    let hours = MedicationService.recentDoseHours(for: name)
    #expect(!hours.isEmpty)
    #expect(hours.allSatisfy { $0 >= 0 && $0 < 24 })
}

// MARK: - consistentMedicationNames

@Test @MainActor func consistentMedicationNamesRequiresMinLogs() {
    let name = "SparseMed_\(UUID().uuidString.prefix(8))"
    _ = MedicationService.logMedication(name: name, doseMg: nil, doseUnit: nil)
    // Only 1 log — should not appear in consistent list (minLogs=3)
    let consistent = MedicationService.consistentMedicationNames(days: 30, minLogs: 3)
    #expect(!consistent.contains(name.capitalized))
}

@Test @MainActor func consistentMedicationNamesAppearsAfterMinLogs() {
    let name = "FreqMed_\(UUID().uuidString.prefix(8))"
    for _ in 0..<3 {
        _ = MedicationService.logMedication(name: name, doseMg: nil, doseUnit: nil)
    }
    let consistent = MedicationService.consistentMedicationNames(days: 30, minLogs: 3)
    #expect(consistent.contains(name.capitalized))
}

// MARK: - dose formatter crash guards (#772 crash hunt)
// `Int(dose)` traps on NaN, ±Infinity, or |dose| >= Int.max. The LLM extractor
// can emit any of these in `params.double("dose")`, so the format helper must
// reject them rather than trap.

@Test func formatDose_wholeNumberDropsDecimal() {
    #expect(MedicationService.formatDose(500) == "500")
    #expect(MedicationService.formatDose(0) == "0")
}

@Test func formatDose_fractionalKeepsDecimal() {
    #expect(MedicationService.formatDose(0.5) == "0.5")
}

@Test func formatDose_infinityDoesNotTrap() {
    // Would have trapped at `Int(.infinity)` pre-#772. Fix returns the placeholder.
    #expect(MedicationService.formatDose(.infinity) == "?")
    #expect(MedicationService.formatDose(-.infinity) == "?")
}

@Test func formatDose_nanDoesNotTrap() {
    // Would have trapped at `Int(.nan)` pre-#772.
    #expect(MedicationService.formatDose(.nan) == "?")
}

@Test func formatDose_hugeFiniteDoesNotTrap() {
    // 1e30 is finite and `1e30 == 1e30.rounded()` is true, so the pre-#772 code
    // path was `String(Int(1e30))` which traps. Fix falls back to String(dose).
    #expect(MedicationService.formatDose(1e30) == String(1e30))
}

@Test func formatDose_negativeZeroNormalizesToZero() {
    // -0.0 == (-0.0).rounded() and |(-0.0)| < Int.max → Int(-0.0) = 0.
    // Locks current behavior so a future formatter swap can't regress to "-0.0".
    #expect(MedicationService.formatDose(-0.0) == "0")
}

@Test @MainActor func logMedication_hugeFiniteDoseDoesNotCrash() {
    // End-to-end: the public entry point must survive a hallucinated huge dose.
    let name = "BigDose_\(UUID().uuidString.prefix(8))"
    let result = MedicationService.logMedication(name: name, doseMg: 1e30, doseUnit: "mg")
    #expect(result.contains(name.capitalized))
    #expect(!result.isEmpty)
}

@Test @MainActor func logMedication_infiniteDoseSilentlyDropsAmount() {
    // Non-finite doses are dropped from the response rather than rendered.
    let name = "InfDose_\(UUID().uuidString.prefix(8))"
    let result = MedicationService.logMedication(name: name, doseMg: .infinity, doseUnit: "mg")
    #expect(result.contains(name.capitalized))
    #expect(!result.contains("("), "non-finite dose must not render a parenthesized amount: \(result)")
}

@Test @MainActor func logMedication_infiniteDoseDoesNotPersistInfinity() {
    // QA scenario 7 — the formatter guard alone was insufficient; pre-fix the
    // raw .infinity was reaching `MedicationLog(doseAmount: .infinity)` and
    // GRDB persisted it. Sanitization now lives at the top of logMedication
    // so the persisted log holds nil instead of a corrupt non-finite.
    let name = "InfPersist_\(UUID().uuidString.prefix(8))"
    _ = MedicationService.logMedication(name: name, doseMg: .infinity, doseUnit: "mg")
    let logs = (try? AppDatabase.shared.fetchMedications(for: name, days: 1)) ?? []
    // Sanity: at least one row landed for the legacy DailyMedication path.
    #expect(!logs.isEmpty)
    for log in logs {
        if let dose = log.doseMg {
            #expect(dose.isFinite, "non-finite dose must not be persisted: got \(dose)")
        }
    }
}

@Test @MainActor func addMedicationProfile_infiniteDoseReturnsErrorWithoutPersisting() {
    // QA scenario 6 — addMedicationProfile must reject non-finite at entry
    // rather than persist a corrupted Medication row.
    let name = "InfProfile_\(UUID().uuidString.prefix(8))"
    let response = MedicationService.addMedicationProfile(name: name, doseAmount: .infinity)
    #expect(response.lowercased().contains("dose"), "rejection must mention dose: \(response)")
    let fetched = try? AppDatabase.shared.findMedication(named: name.lowercased())
    #expect(fetched == nil || fetched?.doseAmount.isFinite == true,
            "non-finite doseAmount must not have been persisted")
}

@Test @MainActor func addMedicationProfile_fractionalDoseRendersDecimal() {
    // Pre-#772, `String(Int(0.5)) = "0"` and the response read "Added X 0mg" —
    // a silent corruption of the user-visible dose. The fix renders "0.5mg".
    let name = "FracDose_\(UUID().uuidString.prefix(8))"
    let response = MedicationService.addMedicationProfile(
        name: name, doseAmount: 0.5, doseUnit: "mg"
    )
    #expect(response.contains("0.5mg"), "fractional dose must render with decimal: \(response)")
    #expect(!response.contains(" 0mg"), "fractional dose must NOT truncate to '0mg': \(response)")
}
