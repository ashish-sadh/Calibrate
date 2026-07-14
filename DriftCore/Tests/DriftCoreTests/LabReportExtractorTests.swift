import Foundation
@testable import DriftCore
import Testing

// Tier-0 tests for the design-665 hybrid lab-extraction decision logic.
// These exercise the pure helpers (no Apple FM call) so they run in the
// fast `swift test` loop on every commit. The FM-backed eval runs as Tier-3
// in FoundationModelsExtractionEvalTests.

// MARK: - shouldFallBackToFM

@Test func shouldFallBackToFM_emptyRegexResult_returnsTrue() {
    #expect(LabExtractionPriority.shouldFallBackToFM(regexBiomarkerIDs: []) == true)
}

@Test func shouldFallBackToFM_fourBiomarkers_returnsTrue() {
    // < 5 biomarkers triggers regardless of which IDs are present
    let ids = ["hba1c", "ldl", "ferritin", "vitamind"]
    #expect(LabExtractionPriority.shouldFallBackToFM(regexBiomarkerIDs: ids) == true)
}

@Test func shouldFallBackToFM_fivePlusButMissingHighPriority_returnsTrue() {
    // 5+ biomarkers but TSH missing → still triggers
    let ids = ["glucose", "hba1c", "ldl", "ferritin", "vitamind", "hemoglobin"]
    #expect(LabExtractionPriority.shouldFallBackToFM(regexBiomarkerIDs: ids) == true)
}

@Test func shouldFallBackToFM_allFiveHighPriorityCovered_returnsFalse() {
    // 5+ biomarkers AND all five high-priority IDs present → skip FM
    let ids = ["glucose", "hba1c", "ldl", "ferritin", "vitamind", "tsh"]
    #expect(LabExtractionPriority.shouldFallBackToFM(regexBiomarkerIDs: ids) == false)
}

@Test func shouldFallBackToFM_caseInsensitiveOnHighPriority() {
    // Regex parsers may emit "HbA1c", "LDL", "VitaminD" — normalize before comparing
    let ids = ["Glucose", "HbA1c", "LDL", "Ferritin", "VitaminD", "TSH"]
    #expect(LabExtractionPriority.shouldFallBackToFM(regexBiomarkerIDs: ids) == false)
}

@Test func highPrioritySetMatchesDesign665Recommendation() {
    // Per #749 + design-665 — the 5 high-priority biomarkers the FM gap-filler
    // exists to recover. Canonical snake_case catalog IDs (2026-07-14 fix): the
    // old camelCase set never matched the regex parser's snake_case IDs, so the
    // subset check could never pass and FM ran on every report. Don't quietly
    // drift the set without revisiting the design.
    let expected: Set<String> = ["hba1c", "ldl_cholesterol", "ferritin", "vitamin_d", "thyroid_tsh"]
    #expect(LabExtractionPriority.highPriority == expected)
}

// MARK: - filterByConfidence

@Test func filterByConfidence_dropsBelowThreshold() {
    let items: [FMLabBiomarker] = [
        FMLabBiomarker(id: "glucose", value: 95, unit: "mg/dL", confidence: 0.95),
        FMLabBiomarker(id: "hba1c", value: 5.4, unit: "%", confidence: 0.7),    // exactly at floor — keep
        FMLabBiomarker(id: "ldl", value: 100, unit: "mg/dL", confidence: 0.69), // below — drop
        FMLabBiomarker(id: "tsh", value: 2.1, unit: "uIU/mL", confidence: 0.3), // ambiguous — drop
    ]
    let kept = LabReportExtractor.filterByConfidence(items)
    #expect(kept.map { $0.id } == ["glucose", "hba1c"])
}

@Test func filterByConfidence_emptyReturnsEmpty() {
    #expect(LabReportExtractor.filterByConfidence([]).isEmpty)
}

@Test func confidenceThresholdIsDesignedSeven() {
    // Pinned by #749: "FM with confidence >=0.7 gate". A future refactor that
    // bumps this must explicitly revisit the design doc.
    #expect(LabReportExtractor.confidenceThreshold == 0.7)
}

// MARK: - buildPrompt — anchored examples for the production prompt

@Test func buildPromptIncludesStatusFlagAddendum() {
    // The "Quest format" retest fix — model must not treat 'Final', 'H', 'L'
    // as biomarker names. Pin the addendum so a prompt-refresh cycle doesn't
    // silently lose this rule.
    let prompt = LabReportExtractor.buildPrompt(for: "any text")
    #expect(prompt.lowercased().contains("ignore status"))
    #expect(prompt.contains("\"Final\""))
    #expect(prompt.contains("\"H\""))
    #expect(prompt.contains("\"L\""))
}

@Test func buildPromptAsksForConfidence() {
    // Without an explicit confidence ask the FM doesn't emit one, and the
    // 0.7 gate becomes a no-op.
    let prompt = LabReportExtractor.buildPrompt(for: "any text")
    #expect(prompt.lowercased().contains("confidence"))
}

@Test func buildPromptIncludesTheInputText() {
    let unique = "MARKER_\(UUID().uuidString.prefix(8))"
    let prompt = LabReportExtractor.buildPrompt(for: unique)
    #expect(prompt.contains(unique))
}
