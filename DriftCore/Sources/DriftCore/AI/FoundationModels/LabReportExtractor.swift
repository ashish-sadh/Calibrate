import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Public output type (available on all OS versions)

/// One biomarker extracted by the FM gap-filler. `confidence` ∈ [0,1].
/// Callers gate at ≥0.7 before merging into the regex result (per design-665).
public struct FMLabBiomarker: Sendable, Equatable {
    public let id: String
    public let value: Double
    public let unit: String
    public let referenceLow: Double?
    public let referenceHigh: Double?
    public let confidence: Double

    public init(
        id: String, value: Double, unit: String,
        referenceLow: Double? = nil, referenceHigh: Double? = nil,
        confidence: Double
    ) {
        self.id = id
        self.value = value
        self.unit = unit
        self.referenceLow = referenceLow
        self.referenceHigh = referenceHigh
        self.confidence = confidence
    }
}

public enum FMLabExtractorError: Error, Sendable {
    case unavailable
    case sessionFailed(String)
}

// MARK: - High-priority biomarkers (the gap-filler decision rule)

/// The five biomarkers the eval (design-665) showed regex misses most often
/// — calling FM when any of these is absent from the regex result is the
/// "missing high-priority" leg of the trigger rule.
public enum LabExtractionPriority {
    /// Canonical snake_case catalog IDs (2026-07-14 fix). Previously these were
    /// lowerCamelCase (`ldl`, `vitamind`, `tsh`) and were compared against the
    /// regex parser's snake_case IDs — so the subset check could NEVER be
    /// satisfied and FM ran on essentially every report even when regex was
    /// complete. Now they match the IDs the parser and catalog actually use.
    public static let highPriority: Set<String> = ["hba1c", "ldl_cholesterol", "ferritin", "vitamin_d", "thyroid_tsh"]
    /// True when the regex result fails either gate from #749:
    /// regex returned <5 biomarkers OR is missing any of the 5 priority IDs.
    /// IDs are canonicalized first so a caller passing camelCase still matches.
    public static func shouldFallBackToFM(regexBiomarkerIDs: [String]) -> Bool {
        if regexBiomarkerIDs.count < 5 { return true }
        let normalized = Set(regexBiomarkerIDs.compactMap { BiomarkerCatalogMap.canonicalID($0) })
        return !highPriority.isSubset(of: normalized)
    }
}

// MARK: - FM session wrapper

public enum LabReportExtractor {

    /// Confidence floor for merging an FM-extracted biomarker into the regex
    /// result. Per design-665 + #749 — values below this get dropped.
    public static let confidenceThreshold: Double = 0.7

    /// Returns the structured FM response. Throws `.unavailable` on iOS<26 /
    /// macOS<26. Callers must apply the confidence gate; the extractor
    /// returns everything the model emitted.
    public static func extract(text: String) async throws -> [FMLabBiomarker] {
#if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            let prompt = buildPrompt(for: text)
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt, generating: FMLabReport.self)
                return response.content.biomarkers.map {
                    FMLabBiomarker(
                        id: $0.id,
                        value: $0.value,
                        unit: $0.unit,
                        referenceLow: $0.referenceLow,
                        referenceHigh: $0.referenceHigh,
                        confidence: $0.confidence
                    )
                }
            } catch {
                throw FMLabExtractorError.sessionFailed("\(error)")
            }
        }
#endif
        throw FMLabExtractorError.unavailable
    }

    /// Filter to biomarkers passing the confidence gate. Public so callers
    /// (and tests) can use the same threshold without re-deriving it.
    public static func filterByConfidence(_ items: [FMLabBiomarker]) -> [FMLabBiomarker] {
        items.filter { $0.confidence >= confidenceThreshold }
    }

    /// Builds the prompt sent to the foundation model. The "ignore status/flag
    /// columns" addendum is the design-665 retest fix for Quest format —
    /// without it the 'Final' / 'H' / 'L' tokens bled into biomarker IDs.
    public static func buildPrompt(for text: String) -> String {
        """
        Extract every biomarker (canonical id, numeric value, unit, reference low/high if listed, confidence 0–1) from the following lab report.

        Use canonical lowerCamelCase IDs like glucose, hba1c, ldl, hdl, totalCholesterol, triglycerides, ferritin, vitaminD, vitaminB12, tsh, freeT4, hemoglobin, alt, ast, iron, sodium, potassium, bun, creatinine.

        IMPORTANT: Ignore status / flag columns. Words like "Final", "H", "L", "High", "Low", "Critical", "Abnormal" are NOT biomarker names — they are result-status markers placed between the test name and the numeric value. Always pair the test name with the numeric value, never with a status flag.

        Emit a confidence between 0 and 1 for each biomarker: 1.0 = test name + unit + numeric value all unambiguous; 0.7 = unit guessed from canonical default; below 0.7 = anything ambiguous (caller will drop it).

        Text:

        \(text)
        """
    }
}

// MARK: - Generable schema (compiled only on macOS 26+ / iOS 26+)

#if canImport(FoundationModels)
@available(macOS 26, iOS 26, *)
@Generable
struct FMLabReport: Sendable {
    @Guide(description: "Lab provider name if listed (LabCorp, Quest, etc.); empty string if generic")
    let labName: String
    @Guide(description: "Specimen / collection date in ISO 8601 (yyyy-MM-dd); empty if not listed")
    let reportDate: String
    @Guide(description: "Every biomarker found on the report. Do not invent biomarkers; do not include status-flag tokens like Final, H, L.")
    let biomarkers: [Biomarker]

    @Generable
    struct Biomarker: Sendable {
        @Guide(description: "Canonical biomarker id — lowerCamelCase like glucose, hba1c, ldl, hdl, totalCholesterol, triglycerides, ferritin, vitaminD, vitaminB12, tsh, freeT4, hemoglobin, alt, ast, iron, sodium, potassium, bun, creatinine")
        let id: String
        @Guide(description: "Numeric result value")
        let value: Double
        @Guide(description: "Result unit string, verbatim from report (e.g. mg/dL, ng/mL, U/L)")
        let unit: String
        @Guide(description: "Lower bound of reference interval; nil if not listed or one-sided range")
        let referenceLow: Double?
        @Guide(description: "Upper bound of reference interval; nil if not listed or one-sided range")
        let referenceHigh: Double?
        @Guide(description: "Confidence in this extraction, 0.0 to 1.0. 1.0 = all fields read unambiguously from the report; below 0.7 = ambiguous and should be discarded.")
        let confidence: Double
    }
}
#endif
