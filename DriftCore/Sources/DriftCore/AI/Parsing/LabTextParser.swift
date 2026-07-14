import Foundation

/// Pure, cross-platform lab-report text parser — the deterministic backbone of
/// biomarker extraction. Ported out of the iOS `LabReportOCR` (2026-07-14) so
/// its accuracy is testable in `swift test` against real report-text fixtures
/// instead of only on-device. PDF text extraction (PDFKit) and photo OCR
/// (Vision) stay in the iOS target; everything from "OCR text" onward lives
/// here.
///
/// The parser is intentionally conservative: it only emits a biomarker when an
/// explicit alias matches and a plausible numeric value sits next to it. The
/// FM / LLM layers (iOS) fill gaps on top of this result; regex always wins on
/// overlap because it never hallucinates.
public enum LabTextParser {

    /// One parsed biomarker reading. `biomarkerId` is always a canonical
    /// snake_case catalog ID (see `BiomarkerCatalogMap`); callers can look it
    /// up directly in `BiomarkerKnowledgeBase.byId`.
    public struct Parsed: Sendable, Equatable {
        public let biomarkerId: String
        public let value: Double
        public let unit: String
        public let referenceLow: Double?
        public let referenceHigh: Double?
        /// A one-sided reference bound, e.g. "< 200" → (.max, 200) stored as
        /// `.high`, "> 40" → `.low`. Kept separate so the UI can render "< 200"
        /// honestly rather than pretending it's a two-sided interval.
        public let referenceOperator: RefOperator?

        public init(biomarkerId: String, value: Double, unit: String,
                    referenceLow: Double? = nil, referenceHigh: Double? = nil,
                    referenceOperator: RefOperator? = nil) {
            self.biomarkerId = biomarkerId
            self.value = value
            self.unit = unit
            self.referenceLow = referenceLow
            self.referenceHigh = referenceHigh
            self.referenceOperator = referenceOperator
        }
    }

    public enum RefOperator: String, Sendable, Equatable {
        case lessThan       // "< 200" — healthy is below referenceHigh
        case greaterThan    // "> 40"  — healthy is above referenceLow
    }

    public struct Output: Sendable, Equatable {
        public let results: [Parsed]
        public let labName: String?
        public let reportDate: String?

        public init(results: [Parsed], labName: String?, reportDate: String?) {
            self.results = results
            self.labName = labName
            self.reportDate = reportDate
        }
    }

    // MARK: - Entry point

    /// Normalize the two micro-sign codepoints OCR emits (U+00B5 µ, U+03BC μ)
    /// to ASCII "u" so unit detection ("µmol/L" → "umol/L") and the SI
    /// conversion table actually fire. Without this, "Creatinine 80 µmol/L"
    /// fell through to the default mg/dL unit and stored 80 mg/dL (2026-07-14).
    public static func normalizeMicroSign(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{00B5}", with: "u")
         .replacingOccurrences(of: "\u{03BC}", with: "u")
    }

    /// Parse OCR/PDF text into biomarker rows. Deterministic and pure.
    public static func parse(text: String) -> Output {
        let rawLines = normalizeMicroSign(text).components(separatedBy: .newlines)
        let lines = rawLines.map { line in
            line.replacingOccurrences(of: #"Page\s*%?\s*\d+\s*of\s*\d+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }

        let labName = detectLabName(from: lines)
        // Indian labs write DD/MM/YYYY; US labs MM/DD/YYYY. When the lab is a
        // known Indian provider, prefer day-first for the ambiguous ≤12/≤12 case.
        let indianLabs: Set<String> = ["Thyrocare", "Dr Lal PathLabs", "SRL Diagnostics",
                                       "Metropolis", "Apollo Diagnostics", "Agilus Diagnostics", "Neuberg Diagnostics"]
        let dayFirst = labName.map { indianLabs.contains($0) } ?? false
        let reportDate = detectReportDate(from: lines, dayFirst: dayFirst)
        let mergedLines = mergeMultiLineEntries(lines)

        var results: [Parsed] = []
        var seen = Set<String>()
        for definition in BiomarkerKnowledgeBase.all {
            if let result = extractBiomarker(definition: definition, mergedLines: mergedLines),
               !seen.contains(result.biomarkerId) {
                seen.insert(result.biomarkerId)
                results.append(result)
            }
        }
        return Output(results: results, labName: labName, reportDate: reportDate)
    }

    // MARK: - Biomarker extraction

    static func extractBiomarker(definition: BiomarkerDefinition, mergedLines: [String]) -> Parsed? {
        guard let aliases = LabAliases.byBiomarkerId[definition.id], !aliases.isEmpty else { return nil }

        struct Candidate {
            let lineIndex: Int
            let aliasLength: Int
            let matchStart: String.Index
        }

        var candidates: [Candidate] = []
        for (i, line) in mergedLines.enumerated() {
            let lower = line.lowercased()
            if lower.contains("collected:") || lower.contains("received:") { continue }
            if isPanelHeaderLine(lower) { continue }
            if lower.contains("printed from") || lower.contains("copyright") || lower.contains("health gorilla") { continue }
            if lower.contains("page ") && lower.contains(" of ") { continue }
            if lower.contains("reference range") && lower.contains("optimal") { continue }

            for alias in aliases {
                if let range = lower.range(of: alias) {
                    // General word-boundary guard: reject a match sitting INSIDE
                    // a larger word ("ast" ⊂ "Fasting", "hb" ⊂ "hba1c", "b12" ⊂
                    // "b1234"). Without it, short aliases produce phantom rows
                    // with a neighbor's value. Only the alphanumeric edges of the
                    // alias are checked, so multi-word aliases still match.
                    if !aliasAtWordBoundary(alias, in: lower, matchRange: range) { continue }
                    if needsWordBoundaryCheck(definition.id, alias: alias, afterMatch: lower[range.upperBound...]) {
                        continue
                    }
                    // No HDL alias may match a "Non-HDL Cholesterol" line — that's
                    // a different biomarker. Applies to every hdl-prefixed alias
                    // ("hdl", "hdl cholesterol", …), keyed on the text before it.
                    if definition.id == "hdl_cholesterol" {
                        let before = String(lower[..<range.lowerBound])
                        if before.hasSuffix("non-") || before.hasSuffix("non ") || before.hasSuffix("non–") { continue }
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

    /// True when `alias` sits at a word boundary in `line` (not embedded in a
    /// larger token). Checks only the alias's own alphanumeric edges: if the
    /// alias starts with a letter/digit, the preceding character must not be
    /// alphanumeric; if it ends with a letter/digit, the following character
    /// must not be a letter. (A trailing digit may legitimately be followed by
    /// a digit only inside the alias, never after it — but medical aliases end
    /// on letters in practice, so we guard the letter case.)
    static func aliasAtWordBoundary(_ alias: String, in line: String, matchRange: Range<String.Index>) -> Bool {
        if let first = alias.first, first.isLetter || first.isNumber {
            if matchRange.lowerBound > line.startIndex {
                let before = line[line.index(before: matchRange.lowerBound)]
                if before.isLetter || before.isNumber { return false }
            }
        }
        if let last = alias.last, last.isLetter || last.isNumber {
            if matchRange.upperBound < line.endIndex {
                let after = line[matchRange.upperBound]
                // A digit right after (e.g. "b12" vs "b1234") or a letter right
                // after (e.g. "hb" vs "hba1c") both mean we're mid-token.
                if after.isLetter { return false }
                if last.isNumber && after.isNumber { return false }
            }
        }
        return true
    }

    /// Detect lines that are panel headers even when PDFKit splits "Collected:"
    /// to the next line.
    static func isPanelHeaderLine(_ lower: String) -> Bool {
        if lower.contains(" and ") && (lower.contains("(dialysis)") || lower.contains("(ms)")) { return true }
        if lower.contains("utc") && (lower.contains("pm") || lower.contains("am")) && !lower.contains("mg/dl") && !lower.contains("g/dl") && !lower.contains("ng/ml") { return true }
        if lower.hasPrefix("iron, tibc") || lower.hasPrefix("lipid panel") || lower.hasPrefix("comprehensive metabolic") { return true }
        if lower.hasPrefix("cbc") || lower.hasPrefix("comp.") { return true }
        return false
    }

    /// Word-boundary checking to prevent false alias matches.
    static func needsWordBoundaryCheck(_ id: String, alias: String, afterMatch: Substring) -> Bool {
        let after = afterMatch.lowercased()
        switch id {
        case "hemoglobin":
            if alias == "hemoglobin" && (after.hasPrefix(" a1c") || after.hasPrefix("a1c")) { return true }
        case "albumin":
            if alias == "albumin" && after.hasPrefix("/globulin") { return true }
        case "iron":
            // Not TIBC, and not "Iron Saturation" / "Iron % Saturation".
            if alias == "iron" && after.hasPrefix(" binding") { return true }
            if alias == "iron" && (after.hasPrefix(" saturation") || after.hasPrefix(" % saturation") || after.hasPrefix(" sat")) { return true }
        case "alt":
            if alias == "alt" && after.hasPrefix("ernative") { return true }
        case "ast":
            if alias == "ast" && after.hasPrefix("hma") { return true }
        case "eosinophil_pct", "monocyte_pct", "basophil_pct", "neutrophil_pct", "lymphocyte_pct":
            let bareNames: Set<String> = ["neutrophils", "lymphocytes", "lymphs", "monocytes", "eosinophils", "basophils", "eos", "basos"]
            if bareNames.contains(alias) {
                if after.contains("(absolute)") || after.contains("(absol") { return true }
                if !after.contains("%") { return true }
            }
        default: break
        }
        return false
    }

    /// Extract the first plausible numeric value (and unit + reference range)
    /// from text after a biomarker name match.
    static func extractFirstValue(afterText: String, fullLine: String, definition: BiomarkerDefinition) -> Parsed? {
        var text = afterText.trimmingCharacters(in: .whitespaces)
        text = text.replacingOccurrences(of: #"(\d),(\d{3})"#, with: "$1$2", options: .regularExpression)

        let numPattern = #"(?:^|[\s,;:]+)[<>]?(\d+\.?\d*)"#
        guard let regex = try? NSRegularExpression(pattern: numPattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)

        for match in regex.matches(in: text, range: nsRange) {
            guard let r = Range(match.range(at: 1), in: text),
                  let value = Double(String(text[r])) else { continue }

            let beforeNum = String(text[text.startIndex..<r.lowerBound]).lowercased()
            let afterNum = String(text[r.upperBound...])
            let afterTrimmed = afterNum.trimmingCharacters(in: .whitespaces)
            let afterNumLower = afterNum.lowercased()

            if afterNumLower.hasPrefix("-oh") || afterNumLower.hasPrefix("-hydroxy") { continue }
            if beforeNum.hasSuffix("/") || afterNum.hasPrefix("/") { continue }
            if value == 0 && afterTrimmed.hasPrefix("1") { continue }
            // Reject a wildly-out-of-scale number ONLY when it isn't an absolute
            // cell count. Indian reports give WBC/platelets as absolute cells
            // ("12500 cells/uL", "450000 /cumm"); without the unit check the
            // guard dropped the real count and grabbed the range low instead.
            if value > 10000 && definition.absoluteHigh < 1000 && !looksLikeAbsoluteCount(afterTrimmed, fullLine) { continue }
            if beforeNum.hasSuffix("-") || beforeNum.hasSuffix("–") { continue }
            if afterNum.hasPrefix(":") { continue }
            if beforeNum.hasSuffix(":") { continue }

            let unit = detectUnit(afterNumber: afterTrimmed, fullLine: fullLine, defaultUnit: definition.unit)
            let ref = extractReferenceRange(from: fullLine)
            return Parsed(
                biomarkerId: definition.id,
                value: value,
                unit: unit,
                referenceLow: ref?.low,
                referenceHigh: ref?.high,
                referenceOperator: ref?.op
            )
        }
        return nil
    }

    /// True when an absolute-cell-count unit sits near the value — the only
    /// case where a 5-figure result is legitimate for a K/uL-scaled marker.
    static func looksLikeAbsoluteCount(_ afterNumber: String, _ fullLine: String) -> Bool {
        let hay = (afterNumber + " " + fullLine).lowercased()
        return hay.contains("cells/ul") || hay.contains("cells/cumm") || hay.contains("/cumm")
            || hay.contains("cumm") || hay.contains("/ul")
    }

    static func detectUnit(afterNumber: String, fullLine: String, defaultUnit: String) -> String {
        let allUnits = [
            "mg/dL", "mg/L", "ng/mL", "ng/dL", "pg/mL", "ug/dL", "mcg/dL", "mcg/L",
            "uIU/mL", "mIU/mL", "mIU/L", "nmol/L", "mmol/L", "umol/L", "pmol/L", "g/dL", "g/L",
            "fL", "pg", "K/uL", "M/uL", "U/L", "IU/L", "IU/mL", "mEq/L", "mm/hr", "mm/h",
            "cells/uL", "x10E3/uL", "x10E6/uL", "10^3/uL", "10^6/uL", "Thousand/uL", "Million/uL",
            "ng/L", "%",
        ]
        let nearText = String(afterNumber.prefix(40))
        for unit in allUnits where nearText.range(of: unit, options: .caseInsensitive) != nil {
            return normalizeUnitString(unit)
        }
        for unit in allUnits where fullLine.range(of: unit, options: .caseInsensitive) != nil {
            return normalizeUnitString(unit)
        }
        return defaultUnit
    }

    static func normalizeUnitString(_ unit: String) -> String {
        let lower = unit.lowercased()
        if lower == "x10e3/ul" || lower == "10^3/ul" || lower == "thousand/ul" { return "K/uL" }
        if lower == "x10e6/ul" || lower == "10^6/ul" || lower == "million/ul" { return "M/uL" }
        if lower == "iu/l" { return "U/L" }
        if lower == "mcg/dl" { return "ug/dL" }
        if lower == "mcg/l" { return "ug/L" }
        if lower == "miu/l" { return "mIU/mL" }
        if lower == "cells/ul" { return "cells/uL" }
        if lower == "mm/h" { return "mm/hr" }
        return unit
    }

    /// Reference-range parser. Handles two-sided (`50 - 180`) AND one-sided
    /// (`< 200`, `> 40`, `>= 39`) ranges — the latter cover most US lab targets
    /// (LDL < 100, HDL > 40) and were previously dropped entirely.
    static func extractReferenceRange(from text: String) -> (low: Double?, high: Double?, op: RefOperator?)? {
        // Two-sided first — most specific.
        if let twoSided = extractTwoSidedRange(from: text) {
            return (twoSided.low, twoSided.high, nil)
        }
        // One-sided: "< 200" / "<=200" (healthy below) or "> 40" / ">= 40" (healthy above).
        // Anchor on a range-y context word or parenthesis so a stray "<5" in a
        // comment doesn't get mistaken for a range.
        let oneSidedPattern = #"(?:range|ref|reference|desirable|optimal|normal|goal|target)?[^\d<>]*([<>]=?)\s*(\d+\.?\d*)"#
        if let regex = try? NSRegularExpression(pattern: oneSidedPattern, options: [.caseInsensitive]) {
            let ns = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: ns) {
                guard let opR = Range(match.range(at: 1), in: text),
                      let numR = Range(match.range(at: 2), in: text),
                      let bound = Double(String(text[numR])), bound < 100000 else { continue }
                let opStr = String(text[opR])
                if opStr.hasPrefix("<") { return (nil, bound, .lessThan) }
                if opStr.hasPrefix(">") { return (bound, nil, .greaterThan) }
            }
        }
        return nil
    }

    private static func extractTwoSidedRange(from text: String) -> (low: Double, high: Double)? {
        // Leading anchor allows start, whitespace, "(", comma or tab so CSV
        // range fields ("…,mg/dL,70-99,") are captured, not just space-padded
        // ranges. Trailing anchor keeps the high bound from bleeding into a
        // following token.
        let pattern = #"(?:^|[\s(,\t])(\d+\.?\d*)\s*[-–]\s*(\d+\.?\d*)(?:\s|$|[),\t\s%])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        var bestMatch: (low: Double, high: Double)?
        for match in regex.matches(in: text, range: nsRange) {
            if let r1 = Range(match.range(at: 1), in: text), let low = Double(String(text[r1])),
               let r2 = Range(match.range(at: 2), in: text), let high = Double(String(text[r2])),
               low < high, high < 1_000_000 {   // WBC / platelet counts run into the thousands
                bestMatch = (low, high)
            }
        }
        return bestMatch
    }

    // MARK: - Line merging

    static func mergeMultiLineEntries(_ lines: [String]) -> [String] {
        var merged: [String] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            guard !line.isEmpty else { merged.append(line); i += 1; continue }

            var combined = line
            var consumed = 0
            for offset in 1...2 {
                guard i + offset < lines.count else { break }
                let next = lines[i + offset].trimmingCharacters(in: .whitespaces)
                guard !next.isEmpty else { break }

                let firstWord = next.split(separator: " ").first.map(String.init) ?? next
                let currentHasResult = lineHasCompleteResult(combined)

                let shouldMerge =
                    next.hasPrefix("(") ||
                    // Trailing-comma continuation ("TESTOSTERONE," + "TOTAL, MS
                    // 656…") — but NOT when this line already carries a value +
                    // unit. Otherwise a CSV row's empty trailing field
                    // ("HbA1c,5.4,%,<5.7,") swallows the next row and every
                    // biomarker inherits a neighbor's unit/range.
                    (!currentHasResult && combined.hasSuffix(",") && next.count < 60) ||
                    (!currentHasResult && isContinuationWord(firstWord)) ||
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

    /// True when `line` already carries a numeric value next to a recognized
    /// unit — i.e. it's a complete result row that shouldn't absorb the next
    /// line. Uses the full unit vocabulary (incl. uIU/mL, ng/dL, pg/mL) so a
    /// TSH row ("2.4 uIU/mL 0.35 - 5.50") isn't merged with the next test's
    /// range.
    static func lineHasCompleteResult(_ line: String) -> Bool {
        guard line.contains(where: \.isNumber) else { return false }
        let cl = line.lowercased()
        let unitTokens = ["mg/dl", "mg/l", "ng/ml", "ng/dl", "pg/ml", "ug/dl", "mcg/dl",
                          "uiu/ml", "miu/ml", "miu/l", "u/l", "iu/l", "g/dl", "g/l",
                          "nmol/l", "mmol/l", "umol/l", "pmol/l", "meq/l", "fl", "pg",
                          "cells/ul", "k/ul", "m/ul", "mm/hr", "mm/h", "%",
                          "thousand", "million", "x10e3", "x10e6", "10^3", "10^6"]
        return unitTokens.contains { cl.contains($0) }
    }

    static func isContinuationWord(_ word: String) -> Bool {
        let upper = word.uppercased()
        let continuations: Set<String> = [
            "TOTAL", "CHOLESTEROL", "RATIO", "PHOSPHATASE", "GLOBULIN", "COUNT",
            "FREE", "AM", "UTC", "BINDING", "NEUTROPHILS", "LYMPHOCYTES", "MONOCYTES",
            "EOSINOPHILS", "BASOPHILS", "CAPACITY", "SULFATE",
            "HORMONE", "PROTEIN", "NITROGEN", "BILIRUBIN", "DIOXIDE", "ACID",
            "TRANSFERASE", "AMINOTRANSFERASE", "DEHYDROEPIANDROSTERONE",
            "Total", "Ratio",
        ]
        return continuations.contains(word) || continuations.contains(upper)
    }

    // MARK: - Lab / date detection

    static func detectLabName(from lines: [String]) -> String? {
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
        // Indian labs — common in the primary user base.
        if text.contains("thyrocare") { return "Thyrocare" }
        if text.contains("dr lal") || text.contains("dr. lal") || text.contains("lalpathlabs") || text.contains("lal path") { return "Dr Lal PathLabs" }
        if text.contains("srl") && text.contains("diagnostic") { return "SRL Diagnostics" }
        if text.contains("metropolis") { return "Metropolis" }
        if text.contains("apollo") && (text.contains("diagnostic") || text.contains("hospital")) { return "Apollo Diagnostics" }
        if text.contains("agilus") { return "Agilus Diagnostics" }
        if text.contains("neuberg") { return "Neuberg Diagnostics" }
        return nil
    }

    static func detectReportDate(from lines: [String], dayFirst: Bool = false) -> String? {
        let monthMap = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]

        for line in lines.prefix(50) {
            let lower = line.lowercased()
            guard lower.contains("collect") else { continue }
            if lower.contains("received") { continue }
            if let date = extractFirstDate(from: line, monthMap: monthMap, dayFirst: dayFirst) { return date }
        }
        for line in lines.prefix(50) {
            let lower = line.lowercased()
            guard lower.contains("received on") || lower.contains("date entered") || lower.contains("reported") else { continue }
            if let date = extractFirstDate(from: line, monthMap: monthMap, dayFirst: dayFirst) { return date }
        }
        for line in lines.prefix(40) {
            let lower = line.lowercased()
            if lower.contains("reference") || lower.contains("range") || lower.contains("result") { continue }
            if let date = extractFirstDate(from: line, monthMap: monthMap, dayFirst: dayFirst) { return date }
        }
        return nil
    }

    static func extractFirstDate(from line: String, monthMap: [String: Int], dayFirst: Bool = false) -> String? {
        // MM/DD/YYYY (US) vs DD/MM/YYYY (Indian/intl). When the first field > 12
        // the order is unambiguous; otherwise use `dayFirst` (set for detected
        // Indian labs) to break the tie instead of always assuming US.
        if let regex = try? NSRegularExpression(pattern: #"(\d{1,2})/(\d{1,2})/(\d{4})"#),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let r1 = Range(match.range(at: 1), in: line), let a = Int(line[r1]),
           let r2 = Range(match.range(at: 2), in: line), let b = Int(line[r2]),
           let r3 = Range(match.range(at: 3), in: line), let y = Int(line[r3]),
           y > 2000 {
            let (m, d): (Int, Int)
            if a > 12 && b <= 12 { (m, d) = (b, a) }        // first field must be the day
            else if b > 12 && a <= 12 { (m, d) = (a, b) }   // second field must be the day → US
            else { (m, d) = dayFirst ? (b, a) : (a, b) }    // ambiguous → lab-origin tiebreak
            if m >= 1, m <= 12, d >= 1, d <= 31 {
                return String(format: "%04d-%02d-%02d", y, m, d)
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"(\d{4})-(\d{2})-(\d{2})"#),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let r1 = Range(match.range(at: 1), in: line), let y = Int(line[r1]),
           let r2 = Range(match.range(at: 2), in: line), let m = Int(line[r2]),
           let r3 = Range(match.range(at: 3), in: line), let d = Int(line[r3]),
           y > 2000, m >= 1, m <= 12, d >= 1, d <= 31 {
            return String(format: "%04d-%02d-%02d", y, m, d)
        }
        let lower = line.lowercased()
        for (abbr, monthNum) in monthMap {
            let patterns = [
                #"\b\#(abbr)\w*\s+(\d{1,2}),?\s+(\d{4})"#,
                #"(\d{1,2})\s+\#(abbr)\w*\s+(\d{4})"#
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
}
