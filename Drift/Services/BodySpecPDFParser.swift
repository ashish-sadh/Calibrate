import Foundation
import PDFKit

/// Parses BodySpec DEXA scan PDF reports and extracts body composition data.
///
/// Expected PDF structure (from pdftotext output):
/// - Summary Results: dates, body fat %, total mass, fat tissue, lean tissue, BMC
/// - Regional Assessment: arms, legs, trunk, android, gynoid - fat%, mass, fat, lean, BMC
/// - Muscle Balance: right/left arm, right/left leg
/// - Supplemental: RMR, android/gynoid %, A/G ratio, VAT mass/volume
enum BodySpecPDFParser {

    struct ParsedScan: Sendable {
        let scanDate: String          // "YYYY-MM-DD"
        let bodyFatPct: Double?
        let totalMassLbs: Double?
        let fatMassLbs: Double?
        let leanMassLbs: Double?
        let bmcLbs: Double?
        let rmrCalories: Double?
        let vatMassLbs: Double?
        let vatVolumeIn3: Double?
        let agRatio: Double?
        let boneDensityTotal: Double?
        let regions: [ParsedRegion]
    }

    struct ParsedRegion: Sendable {
        let name: String              // "arms", "legs", "trunk", "android", "gynoid", "total", "r_arm", "l_arm", "r_leg", "l_leg"
        let fatPct: Double?
        let totalMassLbs: Double?
        let fatMassLbs: Double?
        let leanMassLbs: Double?
        let bmcLbs: Double?
    }

    /// Parse a BodySpec PDF file, extracting ALL scans (the most recent plus historical data).
    static func parse(url: URL) throws -> [ParsedScan] {
        guard url.startAccessingSecurityScopedResource() else {
            throw ParseError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let document = PDFDocument(url: url) else {
            throw ParseError.invalidPDF
        }

        var fullText = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let text = page.string {
                fullText += text + "\n"
            }
        }

        Log.bodyComp.info("Extracted \(fullText.count) chars from BodySpec PDF (\(document.pageCount) pages)")

        return parseScanData(from: fullText)
    }

    // MARK: - Parse Logic

    private static func parseScanData(from text: String) -> [ParsedScan] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }

        // Extract summary table: dates, body fat %, total mass, fat tissue, lean tissue, BMC
        let summaryScans = parseSummaryTable(lines: lines)
        guard !summaryScans.isEmpty else {
            Log.bodyComp.warning("No summary data found in PDF")
            return []
        }

        // The most recent scan (first in the PDF) gets full regional data
        let latestDate = summaryScans[0].date
        let regions = parseRegionalAssessment(lines: lines)
        let muscleBalance = parseMuscleBalance(lines: lines)
        let supplemental = parseSupplemental(lines: lines)

        var scans: [ParsedScan] = []
        for (i, summary) in summaryScans.enumerated() {
            let isLatest = (i == 0)
            scans.append(ParsedScan(
                scanDate: summary.date,
                bodyFatPct: summary.bodyFatPct,
                totalMassLbs: summary.totalMass,
                fatMassLbs: summary.fatMass,
                leanMassLbs: summary.leanMass,
                bmcLbs: summary.bmc,
                rmrCalories: isLatest ? supplemental.rmr.first : (i < supplemental.rmr.count ? supplemental.rmr[i] : nil),
                vatMassLbs: isLatest ? supplemental.vatMass.first : (i < supplemental.vatMass.count ? supplemental.vatMass[i] : nil),
                vatVolumeIn3: isLatest ? supplemental.vatVolume.first : (i < supplemental.vatVolume.count ? supplemental.vatVolume[i] : nil),
                agRatio: isLatest ? supplemental.agRatio.first : (i < supplemental.agRatio.count ? supplemental.agRatio[i] : nil),
                boneDensityTotal: isLatest ? supplemental.boneDensity : nil,
                regions: isLatest ? regions + muscleBalance : []
            ))
        }

        Log.bodyComp.info("Parsed \(scans.count) scans from BodySpec PDF")
        return scans
    }

    // MARK: - Summary Table

    private struct SummaryRow {
        let date: String
        let bodyFatPct: Double?
        let totalMass: Double?
        let fatMass: Double?
        let leanMass: Double?
        let bmc: Double?
    }

    private static func parseSummaryTable(lines: [String]) -> [SummaryRow] {
        // Look for date patterns like "3/6/2026" or "11/16/2025" followed by percentage and mass values
        var rows: [SummaryRow] = []
        let datePattern = #"(\d{1,2}/\d{1,2}/\d{4})"#
        let numberPattern = #"(\d+\.?\d*)"#

        // Find lines with dates in M/D/YYYY format
        var dateLines: [(index: Int, date: String)] = []
        for (i, line) in lines.enumerated() {
            if let match = line.range(of: datePattern, options: .regularExpression) {
                let dateStr = String(line[match])
                dateLines.append((i, dateStr))
            }
        }

        // After "SUMMARY RESULTS" section, look for clustered date + number patterns
        // The PDF has dates listed vertically then numbers listed vertically
        // Structure: date lines, then body fat % lines, then mass lines, etc.

        // Collect all numbers that appear near dates
        var dates: [String] = []
        var bodyFatPcts: [Double] = []
        var totalMasses: [Double] = []
        var fatMasses: [Double] = []
        var leanMasses: [Double] = []
        var bmcs: [Double] = []

        var inSummary = false
        var numberGroups: [[Double]] = []
        var currentNumbers: [Double] = []

        for line in lines {
            if line.contains("SUMMARY RESULTS") { inSummary = true; continue }
            if line.contains("Body Fat Percentile") || line.contains("REGIONAL ASSESSMENT") { inSummary = false }

            guard inSummary else { continue }

            // Check for date
            if let _ = line.range(of: datePattern, options: .regularExpression) {
                let dateStr = extractDate(from: line)
                if let d = dateStr { dates.append(d) }
            }

            // Check for percentage
            if line.hasSuffix("%") {
                if let pct = Double(line.replacingOccurrences(of: "%", with: "")) {
                    bodyFatPcts.append(pct)
                }
            }

            // Check for mass values (numbers like 120.2, 19.8, etc.)
            if let val = Double(line), val > 1 && val < 500 {
                currentNumbers.append(val)
            }
        }

        // The summary has: dates, body fat %s, total masses, fat masses, lean masses, BMCs
        // Try to extract from the full text as a fallback
        if dates.isEmpty {
            // Try harder: find M/D/YYYY patterns throughout
            for line in lines {
                if let d = extractDate(from: line), !dates.contains(d) {
                    // Only dates that appear before "REGIONAL" section
                    dates.append(d)
                }
            }
        }

        // Parse the summary by looking at the structured data
        // BodySpec PDF has: date, bodyFat%, totalMass, fatMass, leanMass, BMC in columns
        // But pdftotext outputs them in rows

        // Use the MCP data we already have as reference, and parse from text numbers
        let allNumbers = lines.compactMap { Double($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }

        // Find the block of numbers after summary dates
        if dates.count >= 1 {
            // body fat percentages come right after the last date
            let pctLines = lines.filter { $0.hasSuffix("%") && !$0.contains("Percentile") && !$0.contains("Fat %") }
            for p in pctLines.prefix(dates.count) {
                if let v = Double(p.replacingOccurrences(of: "%", with: "")) {
                    bodyFatPcts.append(v)
                }
            }

            // Mass values: find numbers between 4.0 and 200.0
            var massValues: [Double] = []
            var afterDates = false
            for line in lines {
                if line.contains("Total Body Fat") { afterDates = true; continue }
                if line.contains("Percentile") { break }
                if afterDates, let v = Double(line), v >= 3.0, v <= 200.0 {
                    massValues.append(v)
                }
            }

            // Group mass values: total, fat, lean, BMC for each scan
            let perScan = 4
            for i in 0..<dates.count {
                let offset = i
                rows.append(SummaryRow(
                    date: dates[i],
                    bodyFatPct: i < bodyFatPcts.count ? bodyFatPcts[i] : nil,
                    totalMass: offset * perScan < massValues.count ? massValues[offset * perScan] : nil,
                    fatMass: offset * perScan + 1 < massValues.count ? massValues[offset * perScan + 1] : nil,
                    leanMass: offset * perScan + 2 < massValues.count ? massValues[offset * perScan + 2] : nil,
                    bmc: offset * perScan + 3 < massValues.count ? massValues[offset * perScan + 3] : nil
                ))
            }
        }

        return rows
    }

    // MARK: - Regional Assessment

    private static func parseRegionalAssessment(lines: [String]) -> [ParsedRegion] {
        // Look for "REGIONAL ASSESSMENT" section
        // Format: Region, Fat%, Total Mass, Fat, Lean, BMC
        var regions: [ParsedRegion] = []
        let regionNames = ["Arms", "Legs", "Trunk", "Android", "Gynoid", "Total"]

        var inRegional = false
        for (i, line) in lines.enumerated() {
            if line.contains("REGIONAL ASSESSMENT") { inRegional = true; continue }
            if line.contains("SUPPLEMENTAL") || line.contains("Muscle Balance") { inRegional = false }

            guard inRegional else { continue }

            for name in regionNames {
                if line == name {
                    // Next values on following lines should be: fat%, total, fat, lean, bmc
                    let values = extractNumbers(from: lines, startingAt: i + 1, count: 5)
                    if values.count >= 5 {
                        regions.append(ParsedRegion(
                            name: name.lowercased(),
                            fatPct: values[0],
                            totalMassLbs: values[1],
                            fatMassLbs: values[2],
                            leanMassLbs: values[3],
                            bmcLbs: values[4]
                        ))
                    }
                }
            }
        }

        return regions
    }

    // MARK: - Muscle Balance (L/R)

    private static func parseMuscleBalance(lines: [String]) -> [ParsedRegion] {
        var regions: [ParsedRegion] = []
        let limbNames = [
            ("Right Arm", "r_arm"), ("Left Arm", "l_arm"),
            ("Right Leg", "r_leg"), ("Left Leg", "l_leg")
        ]

        var inBalance = false
        for (i, line) in lines.enumerated() {
            if line.contains("MUSCLE BALANCE") { inBalance = true; continue }
            if line.contains("REGIONAL FAT TISSUE") || line.contains("REGIONAL LEAN") { inBalance = false }

            guard inBalance else { continue }

            for (pdfName, dbName) in limbNames {
                if line == pdfName {
                    let values = extractNumbers(from: lines, startingAt: i + 1, count: 5)
                    if values.count >= 5 {
                        regions.append(ParsedRegion(
                            name: dbName,
                            fatPct: values[0],
                            totalMassLbs: values[1],
                            fatMassLbs: values[2],
                            leanMassLbs: values[3],
                            bmcLbs: values[4]
                        ))
                    }
                }
            }
        }

        return regions
    }

    // MARK: - Supplemental

    private struct Supplemental {
        var rmr: [Double] = []
        var vatMass: [Double] = []
        var vatVolume: [Double] = []
        var agRatio: [Double] = []
        var boneDensity: Double?
    }

    private static func parseSupplemental(lines: [String]) -> Supplemental {
        var result = Supplemental()

        for (i, line) in lines.enumerated() {
            // RMR values (e.g., "1,311 cal/day")
            if line.contains("cal/day") {
                let cleaned = line.replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: "cal/day", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if let v = Double(cleaned) {
                    result.rmr.append(v)
                }
            }

            // A/G Ratio
            if let v = Double(line), v > 0.5, v < 2.0, i > 0 {
                let prevLine = lines[i - 1]
                if prevLine.contains("%") || result.agRatio.isEmpty {
                    // Could be A/G ratio if near that section
                }
            }

            // VAT Mass
            if line.contains("Mass (lbs)") || (line.contains("Volume") && line.contains("in3")) {
                // Next lines have values
            }

            // Bone density total
            if line == "Total" && i + 1 < lines.count {
                if let v = Double(lines[i + 1]), v > 0.5, v < 2.0 {
                    result.boneDensity = v
                }
            }
        }

        // Parse A/G ratios from supplemental section
        var inSupp = false
        for line in lines {
            if line.contains("SUPPLEMENTAL") { inSupp = true; continue }
            if line.contains("BONE REPORT") || line.contains("MUSCLE BALANCE") { inSupp = false }

            if inSupp {
                if let v = Double(line), v > 0.3, v < 2.5 {
                    result.agRatio.append(v)
                }
            }
        }

        return result
    }

    // MARK: - Helpers

    private static func extractDate(from line: String) -> String? {
        let pattern = #"(\d{1,2})/(\d{1,2})/(\d{4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        let month = String(line[Range(match.range(at: 1), in: line)!])
        let day = String(line[Range(match.range(at: 2), in: line)!])
        let year = String(line[Range(match.range(at: 3), in: line)!])

        return String(format: "%@-%02d-%02d", year, Int(month) ?? 0, Int(day) ?? 0)
    }

    private static func extractNumbers(from lines: [String], startingAt start: Int, count: Int) -> [Double] {
        var numbers: [Double] = []
        var idx = start
        while numbers.count < count && idx < lines.count {
            let cleaned = lines[idx]
                .replacingOccurrences(of: "%", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let v = Double(cleaned) {
                numbers.append(v)
            }
            idx += 1
        }
        return numbers
    }

    enum ParseError: LocalizedError {
        case accessDenied
        case invalidPDF
        case noDataFound

        var errorDescription: String? {
            switch self {
            case .accessDenied: "Could not access the PDF file"
            case .invalidPDF: "The file is not a valid PDF"
            case .noDataFound: "No BodySpec scan data found in the PDF"
            }
        }
    }
}
