import Foundation

// MARK: - Biomarker Extraction + Aliases

extension LabReportOCR {

    // MARK: - Biomarker Extraction

    static func extractBiomarker(definition: BiomarkerDefinition, mergedLines: [String]) -> ExtractedResult? {
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
    static func isPanelHeaderLine(_ lower: String) -> Bool {
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
    static func needsWordBoundaryCheck(_ id: String, alias: String, afterMatch: Substring) -> Bool {
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
    static func extractFirstValue(
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

    static func detectUnit(afterNumber: String, fullLine: String, defaultUnit: String) -> String {
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

    static func normalizeUnitString(_ unit: String) -> String {
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

    static func extractReferenceRange(from text: String) -> (low: Double, high: Double)? {
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
    static let pctBiomarkerIds: Set<String> = [
        "neutrophil_pct", "lymphocyte_pct", "monocyte_pct", "eosinophil_pct", "basophil_pct"
    ]

    // ── IDs that represent absolute WBC differentials ──
    static let absBiomarkerIds: Set<String> = [
        "neutrophils", "lymphocytes", "monocytes", "eosinophils", "basophils"
    ]
}

