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
        return parseLabReport(text: text)
    }

    /// Extract biomarkers from a photo of a lab report.
    static func extract(fromImage image: UIImage) async throws -> ExtractionOutput {
        guard let cgImage = image.cgImage else { throw OCRError.invalidImage }
        let lines = try await recognizeText(in: cgImage)
        guard !lines.isEmpty else { throw OCRError.noTextFound }
        let text = lines.joined(separator: "\n")
        Log.biomarkers.info("Image OCR: \(lines.count) lines recognized")
        return parseLabReport(text: text)
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

    // MARK: - Biomarker Extraction

    private static func extractBiomarker(definition: BiomarkerDefinition, mergedLines: [String]) -> ExtractedResult? {
        // ONLY use explicit aliases — do NOT add definition.name as fallback.
        // This prevents WBC differential absolute biomarkers from matching percentage lines.
        guard let aliases = biomarkerAliases[definition.id], !aliases.isEmpty else { return nil }

        struct Candidate {
            let lineIndex: Int
            let aliasLength: Int
            let matchStart: String.Index
        }

        var candidates: [Candidate] = []
        for (i, line) in mergedLines.enumerated() {
            let lower = line.lowercased()

            // FIX #1: Skip lines that are panel headers or contain timestamps.
            // PDFKit may split "Collected:" onto the next line, so also skip lines
            // that look like section headers with panel keywords.
            if lower.contains("collected:") || lower.contains("received:") { continue }
            if isPanelHeaderLine(lower) { continue }
            if lower.contains("printed from") || lower.contains("copyright") || lower.contains("health gorilla") { continue }
            if lower.contains("page ") && lower.contains(" of ") { continue }
            // Skip comment/interpretation lines
            if lower.contains("reference range") && lower.contains("optimal") { continue }

            for alias in aliases {
                // FIX #5: For percentage biomarkers, check if the line has a number followed by %
                // Quest format: "NEUTROPHILS 57.9 %" — alias "neutrophils" with "%" after the value
                if let range = lower.range(of: alias) {
                    if needsWordBoundaryCheck(definition.id, alias: alias, afterMatch: lower[range.upperBound...]) {
                        continue
                    }
                    candidates.append(Candidate(lineIndex: i, aliasLength: alias.count, matchStart: range.lowerBound))
                }
            }
        }

        for candidate in candidates {
            let line = mergedLines[candidate.lineIndex]
            let lower = line.lowercased()
            let aliasEnd = lower.index(candidate.matchStart, offsetBy: candidate.aliasLength)
            let afterAlias = String(line[aliasEnd...])

            if let result = extractFirstValue(afterText: afterAlias, fullLine: line, definition: definition) {
                return result
            }
        }

        return nil
    }

    /// Detect lines that are panel headers even when PDFKit splits "Collected:" to next line.
    /// E.g., "TESTOSTERONE, FREE (DIALYSIS), TOTAL (MS) AND SEX HORMONE BINDING GLOBULIN /2025 05:05 PM UTC"
    private static func isPanelHeaderLine(_ lower: String) -> Bool {
        // Lines containing multiple panel keywords with "and" are headers
        if lower.contains(" and ") && (lower.contains("(dialysis)") || lower.contains("(ms)")) { return true }
        // Lines with UTC timestamps but no clear result value pattern
        if lower.contains("utc") && (lower.contains("pm") || lower.contains("am")) && !lower.contains("mg/dl") && !lower.contains("g/dl") && !lower.contains("ng/ml") { return true }
        // Lines that look like panel section titles
        if lower.hasPrefix("iron, tibc") || lower.hasPrefix("lipid panel") || lower.hasPrefix("comprehensive metabolic") { return true }
        if lower.hasPrefix("cbc") || lower.hasPrefix("comp.") { return true }
        return false
    }

    /// Word-boundary checking to prevent false alias matches.
    private static func needsWordBoundaryCheck(_ id: String, alias: String, afterMatch: Substring) -> Bool {
        let after = afterMatch.lowercased()
        switch id {
        case "hemoglobin":
            // "hemoglobin" shouldn't match "hemoglobin a1c"
            if alias == "hemoglobin" && (after.hasPrefix(" a1c") || after.hasPrefix("a1c")) { return true }
        case "albumin":
            // "albumin" shouldn't match "albumin/globulin"
            if alias == "albumin" && after.hasPrefix("/globulin") { return true }
        case "iron":
            // "iron" in alias shouldn't match "iron binding" (that's TIBC)
            if alias == "iron" && after.hasPrefix(" binding") { return true }
        case "alt":
            if alias == "alt" && after.hasPrefix("ernative") { return true }
        case "ast":
            if alias == "ast" && after.hasPrefix("hma") { return true }
        case "eosinophil_pct", "monocyte_pct", "basophil_pct", "neutrophil_pct", "lymphocyte_pct":
            // For bare-name aliases (not "xxx %"), require "%" to appear in text after the alias.
            // This prevents "neutrophils" from matching "ABSOLUTE NEUTROPHILS 2548 cells/uL"
            // while allowing it to match "NEUTROPHILS 57.9 %".
            let bareNames: Set<String> = ["neutrophils", "lymphocytes", "lymphs", "monocytes", "eosinophils", "basophils", "eos", "basos"]
            if bareNames.contains(alias) {
                // Must have "%" somewhere after the match, AND must not be an absolute line
                if after.contains("(absolute)") || after.contains("(absol") { return true }
                if !after.contains("%") { return true }
            }
        default: break
        }
        return false
    }

    /// Extract the first numeric value from text after a biomarker name match.
    private static func extractFirstValue(
        afterText: String,
        fullLine: String,
        definition: BiomarkerDefinition
    ) -> ExtractedResult? {
        // Pre-process: strip commas from digit groups (1,234 → 1234)
        var text = afterText.trimmingCharacters(in: .whitespaces)
        text = text.replacingOccurrences(of: #"(\d),(\d{3})"#, with: "$1$2", options: .regularExpression)

        // Pattern: find numbers, optionally preceded by < or >
        let numPattern = #"(?:^|[\s,;:]+)[<>]?(\d+\.?\d*)"#
        guard let regex = try? NSRegularExpression(pattern: numPattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)

        for match in regex.matches(in: text, range: nsRange) {
            guard let r = Range(match.range(at: 1), in: text),
                  let value = Double(String(text[r])) else { continue }

            let beforeNum = String(text[text.startIndex..<r.lowerBound]).lowercased()
            let afterNum = String(text[r.upperBound...])
            let afterTrimmed = afterNum.trimmingCharacters(in: .whitespaces)

            // Skip numbers followed by "-OH" or "-HYDROXY" (part of "25-OH vitamin D")
            let afterNumLower = afterNum.lowercased()
            if afterNumLower.hasPrefix("-oh") || afterNumLower.hasPrefix("-hydroxy") { continue }

            // Skip date components (preceded by "/" or followed by "/")
            if beforeNum.hasSuffix("/") || afterNum.hasPrefix("/") { continue }

            // Skip lab codes like "01" at end of line
            if value == 0 && afterTrimmed.hasPrefix("1") { continue }

            // Skip wildly out-of-range values
            if value > 10000 && definition.absoluteHigh < 1000 { continue }

            // Skip numbers that are second part of reference range ("50-180": skip 180)
            if beforeNum.hasSuffix("-") || beforeNum.hasSuffix("–") { continue }

            // Skip time components (e.g., "05:05" → skip "05" before or after ":")
            if afterNum.hasPrefix(":") { continue }
            if beforeNum.hasSuffix(":") { continue }

            let unit = detectUnit(afterNumber: afterTrimmed, fullLine: fullLine, defaultUnit: definition.unit)
            let refRange = extractReferenceRange(from: fullLine)

            return ExtractedResult(
                biomarkerId: definition.id,
                value: value,
                unit: unit,
                referenceLow: refRange?.low,
                referenceHigh: refRange?.high
            )
        }

        return nil
    }

    private static func detectUnit(afterNumber: String, fullLine: String, defaultUnit: String) -> String {
        let allUnits = [
            "mg/dL", "mg/L", "ng/mL", "ng/dL", "pg/mL", "ug/dL", "mcg/dL", "mcg/L",
            "uIU/mL", "mIU/mL", "mIU/L", "nmol/L", "mmol/L", "g/dL", "fL", "pg",
            "K/uL", "M/uL", "U/L", "IU/L", "mEq/L", "umol/L", "cells/uL",
            "x10E3/uL", "x10E6/uL", "Thousand/uL", "Million/uL", "%",
        ]
        let nearText = String(afterNumber.prefix(40))
        for unit in allUnits {
            if nearText.range(of: unit, options: .caseInsensitive) != nil {
                return normalizeUnitString(unit)
            }
        }
        for unit in allUnits {
            if fullLine.range(of: unit, options: .caseInsensitive) != nil {
                return normalizeUnitString(unit)
            }
        }
        return defaultUnit
    }

    private static func normalizeUnitString(_ unit: String) -> String {
        let lower = unit.lowercased()
        if lower == "x10e3/ul" || lower == "thousand/ul" { return "K/uL" }
        if lower == "x10e6/ul" || lower == "million/ul" { return "M/uL" }
        if lower == "iu/l" { return "U/L" }
        if lower == "mcg/dl" { return "ug/dL" }
        if lower == "mcg/l" { return "ug/L" }
        if lower == "miu/l" { return "mIU/mL" }
        if lower == "cells/ul" { return "cells/uL" }
        return unit
    }

    private static func extractReferenceRange(from text: String) -> (low: Double, high: Double)? {
        let pattern = #"(?:^|[\s(])(\d+\.?\d*)\s*[-–]\s*(\d+\.?\d*)(?:\s|$|[)\s%])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        var bestMatch: (low: Double, high: Double)?
        for match in regex.matches(in: text, range: nsRange) {
            if let r1 = Range(match.range(at: 1), in: text), let low = Double(String(text[r1])),
               let r2 = Range(match.range(at: 2), in: text), let high = Double(String(text[r2])),
               low < high, high < 10000 {
                bestMatch = (low, high)
            }
        }
        return bestMatch
    }

    // MARK: - Biomarker Aliases

    /// Explicit aliases only. No fallback to definition.name — this prevents cross-matching
    /// between percentage and absolute forms of WBC differentials.
    static let biomarkerAliases: [String: [String]] = [
        "total_cholesterol": ["cholesterol, total", "cholesterol,total", "total cholesterol"],
        "hdl_cholesterol": ["hdl cholesterol", "hdl-c", "hdl chol"],
        "ldl_cholesterol": ["ldl cholesterol", "ldl-cholesterol", "ldl-c", "ldl chol calc", "ldl chol"],
        "triglycerides": ["triglycerides", "triglyceride"],
        "non_hdl_cholesterol": ["non hdl cholesterol", "non-hdl cholesterol", "non hdl"],
        "apolipoprotein_b": ["apolipoprotein b", "apo b", "apob"],
        "lipoprotein_a": ["lipoprotein (a)", "lipoprotein(a)", "lp(a)"],
        "glucose": ["glucose"],
        "hba1c": ["hemoglobin a1c", "hba1c", "a1c"],
        "insulin": ["insulin"],
        "homa_ir": ["homa-ir", "homa ir"],
        // Testosterone: "testosterone, total" must match BEFORE "testosterone, free"
        "testosterone_total": ["testosterone, total", "testosterone,total"],
        "free_testosterone": ["testosterone, free", "testosterone,free", "free testosterone"],
        "estradiol": ["estradiol"],
        "shbg": ["sex hormone binding globulin", "shbg"],
        "cortisol": ["cortisol, total", "cortisol,total", "cortisol"],
        "dhea_s": ["dhea sulfate", "dhea-s", "dhea-sulfate"],
        "fsh": ["fsh", "follicle stimulating hormone"],
        "lh": ["luteinizing hormone"],
        "thyroid_tsh": ["tsh"],
        "free_t4": ["free t4", "ft4", "t4, free"],
        "free_t3": ["free t3", "ft3", "t3, free"],
        // FIX #4: "vitamin d,25-oh" is the full test name; "25-oh" alone would match "25" as value
        "vitamin_d": ["vitamin d,25-oh", "vitamin d, 25-oh", "vitamin d 25-oh", "vitamin d"],
        "vitamin_b12": ["vitamin b12", "b12", "cobalamin"],
        "folate": ["folate", "folic acid"],
        "iron": ["iron, total", "iron,total", "serum iron"],
        "ferritin": ["ferritin"],
        "iron_saturation": ["% saturation", "iron saturation", "iron % saturation", "transferrin sat"],
        "calcium": ["calcium"],
        "magnesium": ["magnesium"],
        "zinc": ["zinc"],
        "hs_crp": ["hs crp", "hs-crp", "c-reactive protein"],
        "homocysteine": ["homocysteine"],
        "hemoglobin": ["hemoglobin", "hgb"],
        "hematocrit": ["hematocrit", "hct"],
        "rbc": ["rbc", "red blood cell count", "red blood cell"],
        "mcv": ["mcv"],
        "mch": ["mch"],
        "mchc": ["mchc"],
        "rdw": ["rdw"],
        "platelets": ["platelet count", "platelets", "plt"],
        "wbc": ["wbc", "white blood cell count", "white blood cell"],

        // ── WBC Differentials: ABSOLUTE counts ──
        // Must use "absolute" prefix or "(absolute)" suffix — never bare names.
        "neutrophils": ["absolute neutrophils", "neutrophils (absolute)", "neut abs"],
        "lymphocytes": ["absolute lymphocytes", "lymphocytes (absolute)", "lymphs (absolute)", "lymph abs"],
        "monocytes": ["absolute monocytes", "monocytes (absolute)", "monocytes(absolute)", "monocytes(absol", "mono abs"],
        "eosinophils": ["absolute eosinophils", "eosinophils (absolute)", "eos (absolute)", "eos abs"],
        "basophils": ["absolute basophils", "basophils (absolute)", "baso (absolute)", "baso abs"],

        // ── WBC Differentials: PERCENTAGE ──
        // FIX #5: Quest format is "NEUTROPHILS 57.9 %" — the bare name on a line with "%"
        // Also match "Neutrophils 58 %" from LabCorp. We match bare names BUT only when
        // they appear on lines that contain "%" and a number (validated in extractBiomarkerPct).
        "neutrophil_pct": ["neutrophils", "neutrophil %", "neut %"],
        "lymphocyte_pct": ["lymphocytes", "lymphs", "lymphocyte %", "lymph %"],
        "monocyte_pct": ["monocytes", "monocyte %", "mono %"],
        "eosinophil_pct": ["eosinophils", "eosinophil %", "eos %", "eos"],
        "basophil_pct": ["basophils", "basophil %", "baso %", "basos"],

        "alt": ["alt (sgpt)", "alt(sgpt)", "alt"],
        "ast": ["ast (sgot)", "ast(sgot)", "ast"],
        "alp": ["alkaline phosphatase", "alkaline", "alk phos"],
        "albumin": ["albumin"],
        "globulin": ["globulin, total", "globulin,total", "globulin"],
        "ag_ratio": ["a/g ratio", "albumin/globulin ratio", "albumin/globulin"],
        "total_protein": ["protein, total", "protein,total", "total protein"],
        "bun": ["urea nitrogen (bun)", "urea nitrogen", "bun"],
        "creatinine": ["creatinine"],
        "egfr": ["egfr if nonafricn", "egfr"],
        "sodium": ["sodium"],
        "potassium": ["potassium"],
        "chloride": ["chloride"],
        "co2": ["carbon dioxide, total", "carbon dioxide,total", "carbon dioxide", "co2"],
        "uric_acid": ["uric acid"],
        "total_bilirubin": ["bilirubin, total", "bilirubin,total", "total bilirubin"],
        "ggt": ["ggt", "gamma-glutamyl", "gamma glutamyl"],
        "phosphorus": ["phosphorus", "phosphate"],
        "tibc": ["iron binding capacity", "iron binding", "tibc"],
    ]

    // ── IDs that represent percentage WBC differentials ──
    private static let pctBiomarkerIds: Set<String> = [
        "neutrophil_pct", "lymphocyte_pct", "monocyte_pct", "eosinophil_pct", "basophil_pct"
    ]

    // ── IDs that represent absolute WBC differentials ──
    private static let absBiomarkerIds: Set<String> = [
        "neutrophils", "lymphocytes", "monocytes", "eosinophils", "basophils"
    ]
}
