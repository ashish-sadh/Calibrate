import Foundation
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
        /// True if value was found by LLM enhancement, not regex. Shown as a warning in preview.
        let isAIParsed: Bool

        init(biomarkerId: String, value: Double, unit: String, referenceLow: Double? = nil, referenceHigh: Double? = nil, isAIParsed: Bool = false) {
            self.biomarkerId = biomarkerId
            self.value = value
            self.unit = unit
            self.referenceLow = referenceLow
            self.referenceHigh = referenceHigh
            self.isAIParsed = isAIParsed
        }
    }

    struct ExtractionOutput: Sendable {
        let results: [ExtractedResult]
        let labName: String?
        let reportDate: String?
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
        return await maybeEnhanceWithAI(regexResult: regexResult, rawText: text)
    }

    /// Extract biomarkers from a photo of a lab report.
    static func extract(fromImage image: UIImage) async throws -> ExtractionOutput {
        guard let cgImage = image.cgImage else { throw OCRError.invalidImage }
        let lines = try await recognizeText(in: cgImage)
        guard !lines.isEmpty else { throw OCRError.noTextFound }
        let text = lines.joined(separator: "\n")
        Log.biomarkers.info("Image OCR: \(lines.count) lines recognized")
        let regexResult = parseLabReport(text: text)
        return await maybeEnhanceWithAI(regexResult: regexResult, rawText: text)
    }

    /// Run AI enhancement when available. Gemma (large model): always run to catch what regex misses.
    /// SmolLM (small model): only run when regex found few results — it's less capable.
    private static func maybeEnhanceWithAI(regexResult: ExtractionOutput, rawText: String) async -> ExtractionOutput {
        guard Preferences.aiEnabled, await LocalAIService.shared.isModelLoaded else { return regexResult }
        let isLargeModel = await LocalAIService.shared.isLargeModel
        guard isLargeModel || regexResult.results.count < 10 else { return regexResult }
        return await enhanceWithAI(regexResult: regexResult, rawText: rawText)
    }

    // MARK: - AI Enhancement

    /// Use LLM to find biomarkers missed by regex. Runs on all Gemma uploads (not just <10 results).
    /// Processes OCR text in chunks to fit within the 1776-token prompt limit.
    /// Regex results always take priority on conflicts.
    private static func enhanceWithAI(regexResult: ExtractionOutput, rawText: String) async -> ExtractionOutput {
        let existingIds = Set(regexResult.results.map(\.biomarkerId))
        let allLines = rawText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !allLines.isEmpty else { return regexResult }

        // Compact schema: id:unit — fits in ~400 tokens for all 65 biomarkers
        let schema = BiomarkerKnowledgeBase.all.map { "\($0.id):\($0.unit)" }.joined(separator: ",")
        let systemPrompt = """
        Extract lab test results from the text. \
        Reply ONLY as lines: id|value|unit. One per line. No explanation. \
        Known IDs(unit): \(schema)
        """

        // ~100 lines per chunk leaves ~1200 tokens for OCR content within the 1776-token limit
        let chunkSize = 100
        let maxChunks = 5
        var aiResults: [ExtractedResult] = []

        for chunkStart in stride(from: 0, to: min(allLines.count, chunkSize * maxChunks), by: chunkSize) {
            let chunk = allLines[chunkStart..<min(chunkStart + chunkSize, allLines.count)].joined(separator: "\n")
            let response = await LocalAIService.shared.respondDirect(systemPrompt: systemPrompt, message: chunk)
            let chunkResults = parseAIBiomarkerResponse(response, excluding: existingIds)
            aiResults.append(contentsOf: chunkResults)
        }

        // Deduplicate AI results by biomarkerId (first occurrence wins across chunks)
        var seenAI = Set<String>()
        let dedupedAI = aiResults.filter { seenAI.insert($0.biomarkerId).inserted }

        if dedupedAI.isEmpty { return regexResult }
        Log.biomarkers.info("AI found \(dedupedAI.count) additional biomarkers across \((allLines.count / chunkSize) + 1) chunks")

        // Merge: regex results first (they win on conflicts), then AI-only additions
        var seen = Set(existingIds)
        let additions = dedupedAI.filter { seen.insert($0.biomarkerId).inserted }

        return ExtractionOutput(
            results: regexResult.results + additions,
            labName: regexResult.labName,
            reportDate: regexResult.reportDate
        )
    }

    /// Parse "id|value|unit" lines from LLM response. Marks results as AI-parsed.
    private static func parseAIBiomarkerResponse(_ response: String, excluding existingIds: Set<String>) -> [ExtractedResult] {
        response.components(separatedBy: .newlines).compactMap { line in
            let parts = line.split(separator: "|")
            guard parts.count >= 3 else { return nil }
            let id = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard BiomarkerKnowledgeBase.byId[id] != nil, !existingIds.contains(id) else { return nil }
            guard let value = Double(String(parts[1]).trimmingCharacters(in: .whitespaces)) else { return nil }
            let unit = String(parts[2]).trimmingCharacters(in: .whitespaces)
            return ExtractedResult(biomarkerId: id, value: value, unit: unit, isAIParsed: true)
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

    static func parseLabReport(text: String) -> ExtractionOutput {
        let rawLines = text.components(separatedBy: .newlines)

        // Clean lines: remove page breaks, trim whitespace
        let lines = rawLines.map { line in
            line.replacingOccurrences(of: #"Page\s*%?\s*\d+\s*of\s*\d+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }

        let labName = detectLabName(from: lines)
        let reportDate = detectReportDate(from: lines)

        // Aggressively merge multi-line entries for PDFKit text
        let mergedLines = mergeMultiLineEntries(lines)

        // Extract biomarker values
        var results: [ExtractedResult] = []
        var seen = Set<String>()

        for definition in BiomarkerKnowledgeBase.all {
            if let result = extractBiomarker(definition: definition, mergedLines: mergedLines) {
                if !seen.contains(result.biomarkerId) {
                    seen.insert(result.biomarkerId)
                    results.append(result)
                }
            }
        }

        Log.biomarkers.info("Extracted \(results.count) biomarkers from lab report (lab: \(labName ?? "unknown"))")
        return ExtractionOutput(results: results, labName: labName, reportDate: reportDate)
    }

    // MARK: - Line Merging

    /// Aggressively merge continuation lines from PDFKit text extraction.
    /// PDFKit often splits test names across 2-3 lines: "ABSOLUTE" + "NEUTROPHILS",
    /// "SEX HORMONE" + "BINDING GLOBULIN", "VITAMIN D,25-OH," + "TOTAL,IA"
    private static func mergeMultiLineEntries(_ lines: [String]) -> [String] {
        var merged: [String] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            guard !line.isEmpty else { merged.append(line); i += 1; continue }

            // Try to merge up to 2 continuation lines
            var combined = line
            var consumed = 0

            for offset in 1...2 {
                guard i + offset < lines.count else { break }
                let next = lines[i + offset].trimmingCharacters(in: .whitespaces)
                guard !next.isEmpty else { break }

                let firstWord = next.split(separator: " ").first.map(String.init) ?? next
                // Don't merge if current line already has a result value (contains digits + unit patterns)
                let currentHasResult = combined.contains(where: \.isNumber) &&
                    (combined.lowercased().contains("mg/dl") || combined.lowercased().contains("g/dl") ||
                     combined.lowercased().contains("ng/ml") || combined.lowercased().contains("u/l") ||
                     combined.lowercased().contains("cells/ul") || combined.lowercased().contains("nmol/l") ||
                     combined.lowercased().contains("mmol/l") || combined.lowercased().contains("%") ||
                     combined.lowercased().contains("thousand") || combined.lowercased().contains("million"))

                let shouldMerge =
                    // Parenthetical continuation: "(BUN)", "(Absolute)", "(SGOT)", "(NIH)"
                    next.hasPrefix("(") ||
                    // Previous line ends with comma: "TESTOSTERONE," + "TOTAL, MS 656..."
                    (combined.hasSuffix(",") && next.count < 60) ||
                    // Next line starts with a known continuation word, BUT only if current line
                    // doesn't already have a result (prevents merging "BASOPHILS 31 cells/uL" + "NEUTROPHILS 57.9 %")
                    (!currentHasResult && isContinuationWord(firstWord)) ||
                    // Short all-caps word that is part of a test name, NOT a result line
                    (next.count < 20 && next == next.uppercased() && !next.contains(where: \.isNumber) && !next.contains("%"))

                if shouldMerge {
                    combined += " " + next
                    consumed = offset
                } else {
                    break
                }
            }

            merged.append(combined)
            i += 1 + consumed
        }
        return merged
    }

    /// Words that are clearly continuations of a previous line's test name.
    private static func isContinuationWord(_ word: String) -> Bool {
        let upper = word.uppercased()
        let continuations: Set<String> = [
            "TOTAL", "CHOLESTEROL", "RATIO", "PHOSPHATASE", "GLOBULIN", "COUNT",
            "FREE", "AM", "UTC", "BINDING", "NEUTROPHILS", "LYMPHOCYTES", "MONOCYTES",
            "EOSINOPHILS", "BASOPHILS", "CAPACITY", "SULFATE",
            // PDFKit splits for multi-word test names
            "HORMONE", "PROTEIN", "NITROGEN", "BILIRUBIN", "DIOXIDE", "ACID",
            "TRANSFERASE", "AMINOTRANSFERASE", "DEHYDROEPIANDROSTERONE",
            // Also handle mixed-case from LabCorp
            "Total", "Ratio",
        ]
        return continuations.contains(word) || continuations.contains(upper)
    }

    // MARK: - Lab / Date Detection

    private static func detectLabName(from lines: [String]) -> String? {
        let text = lines.prefix(50).joined(separator: " ").lowercased()
        if text.contains("quest") && (text.contains("diagnostics") || text.contains("result")) { return "Quest Diagnostics" }
        if text.contains("labcorp") || text.contains("laboratory corporation") { return "Labcorp" }
        if text.contains("lab report from labcorp") { return "Labcorp" }
        if text.contains("health gorilla") { return "Quest Diagnostics" }
        if text.contains("whoop") { return "WHOOP" }
        if text.contains("everlywell") { return "Everlywell" }
        if text.contains("insidetracker") { return "InsideTracker" }
        if text.contains("function health") { return "Function Health" }
        if text.contains("marek health") { return "Marek Health" }
        return nil
    }

    private static func detectReportDate(from lines: [String]) -> String? {
        let monthMap = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]

        // Priority 1: "Collection Date:" lines (without "Received" on same line)
        for line in lines.prefix(50) {
            let lower = line.lowercased()
            guard lower.contains("collect") else { continue }
            if lower.contains("received") { continue }
            if let date = extractFirstDate(from: line, monthMap: monthMap) { return date }
        }

        // Priority 2: "Received on" lines
        for line in lines.prefix(50) {
            let lower = line.lowercased()
            guard lower.contains("received on") || lower.contains("date entered") else { continue }
            if let date = extractFirstDate(from: line, monthMap: monthMap) { return date }
        }

        // Fallback: any date in first 40 lines
        for line in lines.prefix(40) {
            let lower = line.lowercased()
            if lower.contains("reference") || lower.contains("range") || lower.contains("result") { continue }
            if let date = extractFirstDate(from: line, monthMap: monthMap) { return date }
        }
        return nil
    }

    private static func extractFirstDate(from line: String, monthMap: [String: Int]) -> String? {
        // MM/DD/YYYY
        if let regex = try? NSRegularExpression(pattern: #"(\d{1,2})/(\d{1,2})/(\d{4})"#),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let r1 = Range(match.range(at: 1), in: line), let m = Int(line[r1]),
           let r2 = Range(match.range(at: 2), in: line), let d = Int(line[r2]),
           let r3 = Range(match.range(at: 3), in: line), let y = Int(line[r3]),
           y > 2000, m >= 1, m <= 12, d >= 1, d <= 31 {
            return String(format: "%04d-%02d-%02d", y, m, d)
        }
        // YYYY-MM-DD
        if let regex = try? NSRegularExpression(pattern: #"(\d{4})-(\d{2})-(\d{2})"#),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let r1 = Range(match.range(at: 1), in: line), let y = Int(line[r1]),
           let r2 = Range(match.range(at: 2), in: line), let m = Int(line[r2]),
           let r3 = Range(match.range(at: 3), in: line), let d = Int(line[r3]),
           y > 2000, m >= 1, m <= 12, d >= 1, d <= 31 {
            return String(format: "%04d-%02d-%02d", y, m, d)
        }
        // "Mon DD, YYYY" or "Month DD, YYYY" (e.g., "Mar 15, 2026", "March 15, 2026")
        let lower = line.lowercased()
        for (abbr, monthNum) in monthMap {
            let patterns = [
                #"\b\#(abbr)\w*\s+(\d{1,2}),?\s+(\d{4})"#,   // "Mar 15, 2026" or "March 15 2026"
                #"(\d{1,2})\s+\#(abbr)\w*\s+(\d{4})"#         // "15 Mar 2026"
            ]
            if let regex = try? NSRegularExpression(pattern: patterns[0]),
               let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let r1 = Range(match.range(at: 1), in: lower), let d = Int(lower[r1]),
               let r2 = Range(match.range(at: 2), in: lower), let y = Int(lower[r2]),
               y > 2000, d >= 1, d <= 31 {
                return String(format: "%04d-%02d-%02d", y, monthNum, d)
            }
            if let regex = try? NSRegularExpression(pattern: patterns[1]),
               let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let r1 = Range(match.range(at: 1), in: lower), let d = Int(lower[r1]),
               let r2 = Range(match.range(at: 2), in: lower), let y = Int(lower[r2]),
               y > 2000, d >= 1, d <= 31 {
                return String(format: "%04d-%02d-%02d", y, monthNum, d)
            }
        }
        return nil
    }


    // Biomarker extraction + aliases in LabReportOCR+Biomarkers.swift
}
