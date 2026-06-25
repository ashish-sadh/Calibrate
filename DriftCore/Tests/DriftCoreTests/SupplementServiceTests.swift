import Foundation
@testable import DriftCore
import Testing

// MARK: - SupplementService Tests

@Test @MainActor func supplementServiceGetStatusReturnsString() {
    let result = SupplementService.getStatus()
    #expect(!result.isEmpty)
    // Either "No supplements set up." or a taken/remaining breakdown
    #expect(result.contains("supplement") || result.contains("Supplement"))
}

@Test @MainActor func supplementServiceMarkTakenUnknownName() {
    let result = SupplementService.markTaken(name: "xyzzy_unknown_supplement_zzz")
    #expect(result.contains("Couldn't find") || result.contains("No supplements"))
}

@Test @MainActor func supplementServiceAddNewSupplement() {
    let name = "TestSupp_Coverage_\(UUID().uuidString.prefix(8))"
    let result = SupplementService.addSupplement(name: name)
    #expect(result.contains("Added"), "Should confirm new supplement was added")
    #expect(result.contains(name.capitalized))
}

@Test @MainActor func supplementServiceAddDuplicateReturnsAlreadyInStack() {
    let name = "TestSupp_Dup_\(UUID().uuidString.prefix(8))"
    _ = SupplementService.addSupplement(name: name)
    let result = SupplementService.addSupplement(name: name)
    #expect(result.contains("already in your stack"))
}

@Test @MainActor func supplementServiceAddSupplementWithDosage() {
    let name = "TestSupp_Dosage_\(UUID().uuidString.prefix(8))"
    let result = SupplementService.addSupplement(name: name, dosage: "500mg")
    #expect(result.contains("Added"))
    #expect(result.contains("500mg"))
}

@Test @MainActor func supplementServiceGetStatusAfterAddReflectsNewEntry() {
    let name = "TestSupp_Status_\(UUID().uuidString.prefix(8))"
    _ = SupplementService.addSupplement(name: name)
    let status = SupplementService.getStatus()
    // After adding, there's at least 1 supplement — should not say "No supplements set up."
    #expect(!status.contains("No supplements set up."))
}

// MARK: - Supplement name extraction from full utterances (#897)
// Deterministic matcher tests on constructed arrays (no DB / no toggle side effects).

@Test @MainActor func matchingSupplementsExtractsSingleFromSentence() {
    let supps = [Supplement(name: "Vitamin D"), Supplement(name: "Omega 3"), Supplement(name: "Creatine")]
    let matched = SupplementService.matchingSupplements(query: "I took my vitamin D this morning", among: supps)
    #expect(matched.map(\.name) == ["Vitamin D"])
}

@Test @MainActor func matchingSupplementsExtractsMultipleFromSentence() {
    let supps = [Supplement(name: "Vitamin D"), Supplement(name: "Omega 3"), Supplement(name: "Creatine")]
    let matched = SupplementService.matchingSupplements(query: "I took my vitamin D and omega 3 this morning", among: supps)
    #expect(Set(matched.map(\.name)) == ["Vitamin D", "Omega 3"])
}

@Test @MainActor func matchingSupplementsHandlesPunctuationAndPartialQuery() {
    let supps = [Supplement(name: "Omega-3"), Supplement(name: "Vitamin D3")]
    // "omega 3" matches stored "Omega-3" despite the hyphen.
    #expect(SupplementService.matchingSupplements(query: "omega 3", among: supps).map(\.name) == ["Omega-3"])
    // A short clean query resolves to the fuller stored name.
    #expect(SupplementService.matchingSupplements(query: "vitamin d", among: supps).map(\.name) == ["Vitamin D3"])
}

@Test @MainActor func matchingSupplementsReturnsEmptyWhenNoneNamed() {
    let supps = [Supplement(name: "Vitamin D"), Supplement(name: "Omega 3")]
    #expect(SupplementService.matchingSupplements(query: "I took my dog for a walk this morning", among: supps).isEmpty)
}

@Test @MainActor func matchingSupplementsIgnoresOneCharacterNames() {
    // A 1-char name must not match just because the utterance ends in " d ".
    let supps = [Supplement(name: "D")]
    #expect(SupplementService.matchingSupplements(query: "I took my vitamin d", among: supps).isEmpty)
}

// End-to-end through the real markTaken path; asserts on the deterministic
// return string (independent of toggle state on the shared in-memory DB).

@Test @MainActor func markTakenSingleSupplementStripsFiller() {
    _ = SupplementService.addSupplement(name: "Vitamin D")
    let result = SupplementService.markTaken(name: "I took my vitamin D this morning")
    #expect(result.hasPrefix("Marked"))
    #expect(result.contains("Vitamin D"))
}

@Test @MainActor func markTakenMarksMultipleSupplementsInOneUtterance() {
    _ = SupplementService.addSupplement(name: "Vitamin D")
    _ = SupplementService.addSupplement(name: "Omega 3")
    let result = SupplementService.markTaken(name: "I took my vitamin D and omega 3 this morning")
    #expect(result.hasPrefix("Marked"))
    #expect(result.contains("Vitamin D"))
    #expect(result.contains("Omega 3"))
}

// Idempotency regression guard: markTaken must SET taken, not toggle. Re-affirming
// "I took it" used to flip it back off (toggleSupplementTaken) while still replying
// "Marked … as taken" — a false confirmation. Uses a unique name so the shared
// in-memory AppDatabase log row is touched only by this test (parallel-safe).
@Test @MainActor func markTakenIsIdempotentAcrossRepeatedAffirmations() {
    let unique = "Zidemprobe"
    _ = SupplementService.addSupplement(name: unique)
    _ = SupplementService.markTaken(name: "I took my \(unique) this morning")
    _ = SupplementService.markTaken(name: "I took my \(unique) this morning")  // second affirmation

    let supplements = (try? AppDatabase.shared.fetchActiveSupplements()) ?? []
    let probeId = supplements.first { $0.name.lowercased() == unique.lowercased() }?.id
    #expect(probeId != nil)
    let logs = (try? AppDatabase.shared.fetchSupplementLogs(for: DateFormatters.todayString)) ?? []
    let probeLog = logs.first { $0.supplementId == probeId }
    #expect(probeLog?.taken == true)  // still taken after two affirmations — not toggled off
}
