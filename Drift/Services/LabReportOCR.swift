import Foundation
import DriftCore
import Vision
import UIKit
import PDFKit

/// Extracts biomarker values from lab report PDFs and photos using OCR and pattern matching.
/// Handles Quest Diagnostics, Labcorp, and generic lab report formats.
enum LabReportOCR {

    struct ExtractedResult: Sendable {
        let biomarkerId: String
        let value: Double
        let unit: String
        let referenceLow: Double?
        let referenceHigh: Double?
        /// True when extracted by LLM (Gemma), not regex.
        let isAIParsed: Bool
        /// LLM extraction confidence 0–1. nil = regex-extracted (treated as high confidence).
        let confidence: Double?

        init(biomarkerId: String, value: Double, unit: String, referenceLow: Double? = nil, referenceHigh: Double? = nil, isAIParsed: Bool = false, confidence: Double? = nil) {
            self.biomarkerId = biomarkerId
            self.value = value
            self.unit = unit
            self.referenceLow = referenceLow
            self.referenceHigh = referenceHigh
            self.isAIParsed = isAIParsed
            self.confidence = confidence
        }
    }

    struct ExtractionOutput: Sendable {
        let results: [ExtractedResult]
        let labName: String?
        let reportDate: String?
        /// True when Gemma ran as primary extractor (show accuracy warning regardless of per-result isAIParsed).
        let isLLMParsed: Bool

        init(results: [ExtractedResult], labName: String?, reportDate: String?, isLLMParsed: Bool = false) {
            self.results = results
            self.labName = labName
            self.reportDate = reportDate
            self.isLLMParsed = isLLMParsed
        }
    }

    enum OCRError: LocalizedError {
        case invalidImage
        case invalidPDF
        case noTextFound
        var errorDescription: String? {
            switch self {
            case .invalidImage: "Could not process the image"
            case .invalidPDF: "Could not read the PDF"
            case .noTextFound: "No readable text found in the document"
            }
        }
    }

    // MARK: - Public API

    /// Extract biomarkers from a PDF file.
    static func extract(fromPDF url: URL) async throws -> ExtractionOutput {
        let text = try extractTextFromPDF(url: url)
        guard !text.isEmpty else { throw OCRError.noTextFound }
        Log.biomarkers.info("PDF OCR: \(text.count) chars extracted")
        let regexResult = parseLabReport(text: text)
        return await buildFinalOutput(regexResult: regexResult, rawText: text)
    }

    /// Extract biomarkers from a photo of a lab report.
    static func extract(fromImage image: UIImage) async throws -> ExtractionOutput {
        guard let cgImage = image.cgImage else { throw OCRError.invalidImage }
        let lines = try await recognizeText(in: cgImage)
        guard !lines.isEmpty else { throw OCRError.noTextFound }
        let text = lines.joined(separator: "\n")
        Log.biomarkers.info("Image OCR: \(lines.count) lines recognized")
        let regexResult = parseLabReport(text: text)
        return await buildFinalOutput(regexResult: regexResult, rawText: text)
    }

    /// Route to the appropriate LLM strategy based on the loaded model.
    /// Step 1 (design-665 / #749): Apple Foundation Models gap-filler — on iOS 26+
    /// run FM whenever regex returned <5 biomarkers OR is missing any high-priority
    /// biomarker (HbA1c, LDL, ferritin, vitaminD, TSH). Confidence ≥0.7 gate.
    /// FM is on-device, zero-cost, and runs without the loaded Gemma model.
    /// Step 2: Gemma 4 (large) — LLM-first if loaded.
    /// Step 3: SmolLM (small) — regex-first supplement when <10 results.
    private static func buildFinalOutput(regexResult: ExtractionOutput, rawText: String) async -> ExtractionOutput {
        let afterFM = await applyFMGapFillerIfNeeded(regexResult: regexResult, rawText: rawText)
        guard Preferences.aiEnabled, await LocalAIService.shared.isModelLoaded else { return afterFM }
        if await LocalAIService.shared.isLargeModel {
            return await extractLLMFirst(regexResult: afterFM, rawText: rawText)
        }
        guard afterFM.results.count < 10 else { return afterFM }
        return await enhanceWithAI(regexResult: afterFM, rawText: rawText)
    }

    // MARK: - Apple FM Gap-Filler (design-665 hybrid path)

    /// Gap-filler stage that runs the Apple Foundation Models extractor when
    /// the regex result is short or missing a high-priority biomarker. FM
    /// extractions are merged into the regex result only when their
    /// confidence meets `LabReportExtractor.confidenceThreshold`, and regex
    /// always wins on overlap (FM is a refinement layer, not a replacement).
    private static func applyFMGapFillerIfNeeded(regexResult: ExtractionOutput, rawText: String) async -> ExtractionOutput {
        let regexIDs = regexResult.results.map { $0.biomarkerId }
        guard LabExtractionPriority.shouldFallBackToFM(regexBiomarkerIDs: regexIDs) else { return regexResult }

        let fmResults: [FMLabBiomarker]
        do {
            fmResults = try await LabReportExtractor.extract(text: rawText)
        } catch FMLabExtractorError.unavailable {
            return regexResult  // iOS<26 / macOS<26 — FM not present
        } catch {
            Log.biomarkers.info("FM extractor failed, keeping regex result: \(String(describing: error))")
            return regexResult
        }

        let gated = LabReportExtractor.filterByConfidence(fmResults)
        // FM is prompted to emit lowerCamelCase IDs (ldl, vitaminD, tsh);
        // canonicalize to the snake_case catalog IDs so (a) FM rows dedup
        // against the regex rows they overlap, (b) unknown IDs are dropped
        // instead of saved as un-nameable rows, and (c) the UI can range-check
        // them. Pre-2026-07-14 this mismatch caused duplicate + orphan rows.
        let existing = Set(regexResult.results.map { $0.biomarkerId })
        var merged = regexResult.results
        var addedCanonical = Set<String>()
        for fm in gated {
            guard let canonical = BiomarkerCatalogMap.canonicalID(fm.id) else {
                Log.biomarkers.info("FM emitted unknown biomarker id '\(fm.id)' — dropped")
                continue
            }
            guard !existing.contains(canonical), addedCanonical.insert(canonical).inserted else { continue }
            merged.append(ExtractedResult(
                biomarkerId: canonical,
                value: fm.value,
                unit: fm.unit,
                referenceLow: fm.referenceLow,
                referenceHigh: fm.referenceHigh,
                isAIParsed: true,
                confidence: fm.confidence
            ))
        }
        Log.biomarkers.info("FM gap-filler: regex=\(regexResult.results.count) + fm-gated=\(gated.count) → \(merged.count)")
        return ExtractionOutput(
            results: merged,
            labName: regexResult.labName,
            reportDate: regexResult.reportDate,
            isLLMParsed: regexResult.isLLMParsed || !gated.isEmpty
        )
    }

    // MARK: - Gemma LLM-First Pipeline

    /// Gemma 4 primary path: LLM extracts all biomarkers first, regex fills gaps and validates.
    /// For each biomarker found by both: LLM wins when confidence ≥ 0.85, otherwise regex wins.
    /// LLM-only results are included when confidence ≥ 0.6.
    /// Processes OCR text in 100-line chunks (up to 10 chunks = ~5000 tokens max).
    private static func extractLLMFirst(regexResult: ExtractionOutput, rawText: String) async -> ExtractionOutput {
        let allLines = rawText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !allLines.isEmpty else { return regexResult }

        let schema = BiomarkerKnowledgeBase.all.map { "\($0.id):\($0.unit)" }.joined(separator: ",")
        let systemPrompt = """
        Extract lab test results from the text. \
        Reply ONLY as lines: id|value|unit|confidence where confidence is 0.0-1.0. One per line. No explanation. \
        Known IDs(unit): \(schema)
        """

        let chunkSize = 100
        let maxChunks = 10
        var llmResults: [ExtractedResult] = []
        var reportDate = regexResult.reportDate

        for chunkStart in stride(from: 0, to: min(allLines.count, chunkSize * maxChunks), by: chunkSize) {
            let chunk = allLines[chunkStart..<min(chunkStart + chunkSize, allLines.count)].joined(separator: "\n")
            let response = await LocalAIService.shared.respondDirect(systemPrompt: systemPrompt, message: chunk)
            llmResults.append(contentsOf: parseLLMBiomarkerResponse(response))

            // LLM date fallback: ask first chunk if regex found nothing
            if reportDate == nil && chunkStart == 0 {
                reportDate = await extractDateWithLLM(chunk: chunk)
            }
        }

        // Deduplicate LLM results per biomarkerId — keep highest confidence across chunks
        var llmMap: [String: ExtractedResult] = [:]
        for r in llmResults {
            if let existing = llmMap[r.biomarkerId] {
                if (r.confidence ?? 0) > (existing.confidence ?? 0) { llmMap[r.biomarkerId] = r }
            } else {
                llmMap[r.biomarkerId] = r
            }
        }

        // Merge: for each biomarker, pick higher-confidence source
        var merged: [ExtractedResult] = []
        var seen = Set<String>()

        for regexR in regexResult.results {
            if let llmR = llmMap[regexR.biomarkerId], (llmR.confidence ?? 0) >= 0.85 {
                merged.append(llmR)
            } else {
                merged.append(regexR)
            }
            seen.insert(regexR.biomarkerId)
        }

        // Add LLM-only results that regex missed (confidence threshold prevents hallucinations)
        for (id, llmR) in llmMap where !seen.contains(id) {
            if (llmR.confidence ?? 0) >= 0.6 { merged.append(llmR) }
        }

        Log.biomarkers.info("LLM-first: \(llmMap.count) LLM, \(regexResult.results.count) regex → \(merged.count) merged")
        return ExtractionOutput(results: merged, labName: regexResult.labName, reportDate: reportDate, isLLMParsed: true)
    }

    /// Ask LLM to return the report date from the first chunk of OCR text.
    /// Returns YYYY-MM-DD string or nil if the model can't determine it.
    private static func extractDateWithLLM(chunk: String) async -> String? {
        let response = await LocalAIService.shared.respondDirect(
            systemPrompt: "Return the lab report date as YYYY-MM-DD. If no date found, return null.",
            message: chunk
        )
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"(\d{4})-(\d{2})-(\d{2})"#),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let range = Range(match.range, in: trimmed),
              let y = Int(trimmed[Range(match.range(at: 1), in: trimmed)!]),
              let m = Int(trimmed[Range(match.range(at: 2), in: trimmed)!]),
              let d = Int(trimmed[Range(match.range(at: 3), in: trimmed)!]),
              y > 2000, m >= 1, m <= 12, d >= 1, d <= 31
        else { return nil }
        return String(trimmed[range])
    }

    // MARK: - SmolLM Supplemental Path

    /// SmolLM path: regex already extracted, AI only adds what was missed (≥10 regex results skips AI).
    /// Regex always wins on conflicts — SmolLM is less reliable on structured extraction.
    private static func enhanceWithAI(regexResult: ExtractionOutput, rawText: String) async -> ExtractionOutput {
        let existingIds = Set(regexResult.results.map(\.biomarkerId))
        let allLines = rawText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !allLines.isEmpty else { return regexResult }

        let schema = BiomarkerKnowledgeBase.all.map { "\($0.id):\($0.unit)" }.joined(separator: ",")
        let systemPrompt = """
        Extract lab test results from the text. \
        Reply ONLY as lines: id|value|unit|confidence where confidence is 0.0-1.0. One per line. No explanation. \
        Known IDs(unit): \(schema)
        """

        let chunkSize = 100
        let maxChunks = 5
        var aiResults: [ExtractedResult] = []

        for chunkStart in stride(from: 0, to: min(allLines.count, chunkSize * maxChunks), by: chunkSize) {
            let chunk = allLines[chunkStart..<min(chunkStart + chunkSize, allLines.count)].joined(separator: "\n")
            let response = await LocalAIService.shared.respondDirect(systemPrompt: systemPrompt, message: chunk)
            let chunkResults = parseLLMBiomarkerResponse(response).filter { !existingIds.contains($0.biomarkerId) }
            aiResults.append(contentsOf: chunkResults)
        }

        var seenAI = Set<String>()
        let additions = aiResults.filter { seenAI.insert($0.biomarkerId).inserted }
        guard !additions.isEmpty else { return regexResult }

        Log.biomarkers.info("SmolLM added \(additions.count) biomarkers")
        return ExtractionOutput(
            results: regexResult.results + additions,
            labName: regexResult.labName,
            reportDate: regexResult.reportDate
        )
    }

    /// Parse "id|value|unit|confidence" lines from LLM response. Confidence column is optional.
    /// Internal (not private) so the test suite can verify parsing without a live LLM.
    static func parseLLMBiomarkerResponse(_ response: String) -> [ExtractedResult] {
        response.components(separatedBy: .newlines).compactMap { line in
            let parts = line.split(separator: "|")
            guard parts.count >= 3 else { return nil }
            let id = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard BiomarkerKnowledgeBase.byId[id] != nil else { return nil }
            guard let value = Double(String(parts[1]).trimmingCharacters(in: .whitespaces)) else { return nil }
            let unit = String(parts[2]).trimmingCharacters(in: .whitespaces)
            let confidence = parts.count >= 4 ? Double(String(parts[3]).trimmingCharacters(in: .whitespaces)) : nil
            return ExtractedResult(biomarkerId: id, value: value, unit: unit, isAIParsed: true, confidence: confidence)
        }
    }

    // MARK: - Text Extraction

    private static func extractTextFromPDF(url: URL) throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let doc = PDFDocument(url: url) else { throw OCRError.invalidPDF }
        var text = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let pageText = page.string {
                text += pageText + "\n"
            }
        }
        return text
    }

    private static func recognizeText(in image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Lab Report Parsing (internal for testing)

    /// Deterministic regex parse. Delegates the pure text logic to DriftCore's
    /// `LabTextParser` (2026-07-14) so accuracy is testable in `swift test`
    /// against real report-text fixtures; this shim only maps the shared
    /// `LabTextParser.Parsed` onto the iOS `ExtractedResult`.
    static func parseLabReport(text: String) -> ExtractionOutput {
        let parsed = LabTextParser.parse(text: text)
        let results = parsed.results.map { p in
            ExtractedResult(
                biomarkerId: p.biomarkerId,
                value: p.value,
                unit: p.unit,
                referenceLow: p.referenceLow,
                referenceHigh: p.referenceHigh
            )
        }
        Log.biomarkers.info("Extracted \(results.count) biomarkers from lab report (lab: \(parsed.labName ?? "unknown"))")
        return ExtractionOutput(results: results, labName: parsed.labName, reportDate: parsed.reportDate)
    }

}
