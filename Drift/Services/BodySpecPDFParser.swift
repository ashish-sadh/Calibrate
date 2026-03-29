import Foundation
import PDFKit

/// Parses BodySpec DEXA scan PDF reports.
///
/// The pdftotext output has a known structure where the summary table
/// lists dates, then body fat %, then total mass, fat, lean, BMC
/// each as separate groups of lines (one value per scan per line).
enum BodySpecPDFParser {

    struct ParsedScan: Sendable {
        let scanDate: String
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
        let name: String
        let fatPct: Double?
        let totalMassLbs: Double?
        let fatMassLbs: Double?
        let leanMassLbs: Double?
        let bmcLbs: Double?
    }

    static func parse(url: URL) throws -> [ParsedScan] {
        guard url.startAccessingSecurityScopedResource() else { throw ParseError.accessDenied }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let document = PDFDocument(url: url) else { throw ParseError.invalidPDF }

        var fullText = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let text = page.string {
                fullText += text + "\n"
            }
        }

        Log.bodyComp.info("PDF text: \(fullText.count) chars, \(document.pageCount) pages")
        return parseFromText(fullText)
    }

    /// Main parse logic. Works on the raw text from pdftotext.
    static func parseFromText(_ text: String) -> [ParsedScan] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }

        // 1. Find all dates in the summary section (M/D/YYYY format)
        var dates: [String] = [] // YYYY-MM-DD format
        var inSummary = false

        for line in lines {
            if line.contains("SUMMARY RESULTS") { inSummary = true; continue }
            if line.contains("Body Fat Percentile") || line.contains("REGIONAL") { inSummary = false }
            if inSummary, let d = parseDate(line) {
                dates.append(d)
            }
        }

        guard !dates.isEmpty else {
            Log.bodyComp.warning("No dates found in summary section")
            return []
        }

        let scanCount = dates.count
        Log.bodyComp.info("Found \(scanCount) scan dates: \(dates)")

        // 2. Extract the numeric columns from summary.
        // After dates, the PDF has groups of numbers:
        //   body fat %: "16.4%", "21.0%", "25.0%", "25.2%"
        //   total mass: 120.2, 122.3, 129.2, 130.3
        //   fat tissue: 19.8, 25.6, 32.3, 32.8
        //   lean tissue: 95.5, 91.5, 91.8, 92.4
        //   BMC: 4.9, 5.1, 5.1, 5.1
        //
        // These appear as individual lines in the text.

        var summaryNumbers: [Double] = []
        var bodyFatPcts: [Double] = []
        inSummary = false
        var pastDates = false

        for line in lines {
            if line.contains("SUMMARY RESULTS") { inSummary = true; continue }
            if line.contains("Body Fat Percentile") || line.contains("REGIONAL") { inSummary = false }
            guard inSummary else { continue }

            // Skip header labels
            if line.contains("Measured Date") || line.contains("Total Body Fat")
                || line.contains("Total Mass") || line.contains("Fat Tissue")
                || line.contains("Lean Tissue") || line.contains("Bone Mineral")
                || line.contains("Content") || line.contains("Quantification")
                || line.contains("This table") || line.contains("baseline") { continue }

            // Check for percentage values
            if line.hasSuffix("%") {
                let cleaned = line.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
                if let v = Double(cleaned) {
                    bodyFatPcts.append(v)
                    continue
                }
            }

            // Skip date lines (already captured)
            if parseDate(line) != nil { pastDates = true; continue }

            // Numeric values
            let cleaned = line.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
            if let v = Double(cleaned), v > 0, v < 500 {
                summaryNumbers.append(v)
            }
        }

        Log.bodyComp.info("Summary: \(bodyFatPcts.count) fat%, \(summaryNumbers.count) mass values")

        // Build scans from extracted data
        // summaryNumbers should be: [totalMass x N, fatMass x N, leanMass x N, BMC x N]
        var scans: [ParsedScan] = []

        for i in 0..<scanCount {
            let totalMass = (i < summaryNumbers.count) ? summaryNumbers[i] : nil
            let fatMass = (scanCount + i < summaryNumbers.count) ? summaryNumbers[scanCount + i] : nil
            let leanMass = (scanCount * 2 + i < summaryNumbers.count) ? summaryNumbers[scanCount * 2 + i] : nil
            let bmc = (scanCount * 3 + i < summaryNumbers.count) ? summaryNumbers[scanCount * 3 + i] : nil

            scans.append(ParsedScan(
                scanDate: dates[i],
                bodyFatPct: i < bodyFatPcts.count ? bodyFatPcts[i] : nil,
                totalMassLbs: totalMass,
                fatMassLbs: fatMass,
                leanMassLbs: leanMass,
                bmcLbs: bmc,
                rmrCalories: nil, vatMassLbs: nil, vatVolumeIn3: nil,
                agRatio: nil, boneDensityTotal: nil,
                regions: i == 0 ? parseRegions(lines: lines) : []
            ))
        }

        // Parse supplemental data for all scans
        let rmrs = parseValues(lines: lines, after: "Resting Metabolic Rate", suffix: "cal/day", count: scanCount)
        let agRatios = parseColumnValues(lines: lines, section: "A/G Ratio", count: scanCount)
        let vatMasses = parseColumnValues(lines: lines, section: "Mass (lbs)", count: scanCount)
        let vatVolumes = parseColumnValues(lines: lines, section: "Volume (in3)", count: scanCount)

        // Update scans with supplemental
        for i in 0..<scans.count {
            var s = scans[i]
            s = ParsedScan(
                scanDate: s.scanDate, bodyFatPct: s.bodyFatPct,
                totalMassLbs: s.totalMassLbs, fatMassLbs: s.fatMassLbs,
                leanMassLbs: s.leanMassLbs, bmcLbs: s.bmcLbs,
                rmrCalories: i < rmrs.count ? rmrs[i] : nil,
                vatMassLbs: i < vatMasses.count ? vatMasses[i] : nil,
                vatVolumeIn3: i < vatVolumes.count ? vatVolumes[i] : nil,
                agRatio: i < agRatios.count ? agRatios[i] : nil,
                boneDensityTotal: nil, regions: scans[i].regions
            )
            scans[i] = s
        }

        return scans
    }

    // MARK: - Regional Assessment

    private static func parseRegions(lines: [String]) -> [ParsedRegion] {
        var regions: [ParsedRegion] = []

        // Regional Assessment table: region name followed by values
        let mainRegions = ["Arms", "Legs", "Trunk", "Android", "Gynoid"]
        var inRegional = false

        for (i, line) in lines.enumerated() {
            if line.contains("REGIONAL ASSESSMENT") { inRegional = true; continue }
            if line.contains("SUPPLEMENTAL") || line.contains("REGIONAL FAT TISSUE") { inRegional = false }
            guard inRegional else { continue }

            for name in mainRegions {
                if line == name {
                    let values = grabNumbers(from: lines, startingAt: i + 1, count: 5)
                    if values.count >= 5 {
                        regions.append(ParsedRegion(
                            name: name.lowercased(), fatPct: values[0],
                            totalMassLbs: values[1], fatMassLbs: values[2],
                            leanMassLbs: values[3], bmcLbs: values[4]
                        ))
                    }
                }
            }
            // Also capture "Total" in regional section
            if line == "Total" && inRegional {
                let values = grabNumbers(from: lines, startingAt: i + 1, count: 5)
                if values.count >= 5 {
                    regions.append(ParsedRegion(
                        name: "total", fatPct: values[0],
                        totalMassLbs: values[1], fatMassLbs: values[2],
                        leanMassLbs: values[3], bmcLbs: values[4]
                    ))
                }
            }
        }

        // Muscle Balance: R/L arms and legs
        let limbPairs = [("Right Arm", "r_arm"), ("Left Arm", "l_arm"), ("Right Leg", "r_leg"), ("Left Leg", "l_leg")]
        var inBalance = false

        for (i, line) in lines.enumerated() {
            if line.contains("MUSCLE BALANCE") { inBalance = true; continue }
            if line.contains("REGIONAL FAT TISSUE") || line.contains("REGIONAL LEAN") { inBalance = false }
            guard inBalance else { continue }

            for (pdfName, dbName) in limbPairs {
                if line == pdfName {
                    let values = grabNumbers(from: lines, startingAt: i + 1, count: 5)
                    if values.count >= 5 {
                        regions.append(ParsedRegion(
                            name: dbName, fatPct: values[0],
                            totalMassLbs: values[1], fatMassLbs: values[2],
                            leanMassLbs: values[3], bmcLbs: values[4]
                        ))
                    }
                }
            }
        }

        Log.bodyComp.info("Parsed \(regions.count) regions")
        return regions
    }

    // MARK: - Helpers

    private static func parseDate(_ line: String) -> String? {
        let pattern = #"^(\d{1,2})/(\d{1,2})/(\d{4})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        let m = String(line[Range(match.range(at: 1), in: line)!])
        let d = String(line[Range(match.range(at: 2), in: line)!])
        let y = String(line[Range(match.range(at: 3), in: line)!])
        return String(format: "%@-%02d-%02d", y, Int(m) ?? 0, Int(d) ?? 0)
    }

    private static func grabNumbers(from lines: [String], startingAt start: Int, count: Int) -> [Double] {
        var nums: [Double] = []
        var idx = start
        while nums.count < count && idx < lines.count {
            let cleaned = lines[idx].replacingOccurrences(of: "%", with: "")
                .replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
            if let v = Double(cleaned) { nums.append(v) }
            idx += 1
        }
        return nums
    }

    private static func parseValues(lines: [String], after keyword: String, suffix: String, count: Int) -> [Double] {
        var values: [Double] = []
        for line in lines {
            if line.contains(suffix) {
                let cleaned = line.replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: suffix, with: "").trimmingCharacters(in: .whitespaces)
                if let v = Double(cleaned) { values.append(v) }
            }
        }
        return values
    }

    private static func parseColumnValues(lines: [String], section: String, count: Int) -> [Double] {
        var values: [Double] = []
        var found = false
        for line in lines {
            if line.contains(section) { found = true; continue }
            if found {
                let cleaned = line.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                if let v = Double(cleaned) {
                    values.append(v)
                    if values.count >= count { break }
                } else if !cleaned.isEmpty {
                    break // Hit non-numeric line
                }
            }
        }
        return values
    }

    enum ParseError: LocalizedError {
        case accessDenied, invalidPDF, noDataFound
        var errorDescription: String? {
            switch self {
            case .accessDenied: "Could not access the PDF file"
            case .invalidPDF: "Not a valid PDF"
            case .noDataFound: "No BodySpec data found"
            }
        }
    }
}
