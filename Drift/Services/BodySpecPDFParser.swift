import Foundation
import DriftCore
import PDFKit

/// Parses BodySpec DEXA scan PDF reports using PDFKit text extraction.
///
/// PDFKit extracts text differently from pdftotext - data often appears on
/// single lines with values concatenated. This parser handles that format.
enum BodySpecPDFParser {

    /// Top-level types live in DriftCore so AppDatabase can return them.
    typealias ParsedScan = BodySpecParsedScan
    typealias ParsedRegion = BodySpecParsedRegion

    static func parse(url: URL) throws -> [ParsedScan] {
        guard url.startAccessingSecurityScopedResource() else { throw ParseError.accessDenied }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let doc = PDFDocument(url: url) else { throw ParseError.invalidPDF }

        var fullText = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let text = page.string {
                fullText += text + "\n"
            }
        }

        Log.bodyComp.info("PDF: \(fullText.count) chars, \(doc.pageCount) pages")

        let scans = parseText(fullText)
        if scans.isEmpty {
            throw ParseError.noDataFound
        }
        return scans
    }

    static func parseText(_ text: String) -> [ParsedScan] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }

        // Step 1: Find scan summary data.
        // PDFKit gives us lines like:
        //   "16.4% 19.8 95.5 4.9"                          (first scan: bf%, fat, lean, bmc)
        //   "3/6/2026 1/25/2026 ... 120.2 122.3 ... 21.0% 25.6 91.5 5.1"  (dates + totals + 2nd scan)
        //   "25.0% 32.3 91.8 5.1"                          (3rd scan)
        //   "25.2% 32.8 92.4 5.1"                          (4th scan)

        struct ScanData {
            var date: String = ""
            var bodyFatPct: Double?
            var totalMassLbs: Double?
            var fatMassLbs: Double?
            var leanMassLbs: Double?
            var bmcLbs: Double?
        }

        var scanDatas: [ScanData] = []
        var scanDates: [String] = []
        var totalMasses: [Double] = []
        var pctAndValues: [(pct: Double, vals: [Double])] = []

        // Find SUMMARY RESULTS section
        var inSummary = false
        for line in lines {
            if line.contains("SUMMARY RESULTS") { inSummary = true; continue }
            if line.contains("Percentile Chart") || line.contains("REGIONAL") { inSummary = false }
            guard inSummary else { continue }

            // Skip headers/descriptions
            if line.contains("Measured Date") || line.contains("Total Body Fat") || line.contains("Total Mass")
                || line.contains("Fat Tissue") || line.contains("Lean Tissue") || line.contains("Bone Mineral")
                || line.contains("Content") || line.contains("This table") || line.contains("baseline")
                || line.contains("Quantification") || line.isEmpty { continue }

            let tokens = tokenize(line)

            // Extract dates from this line
            let datePattern = #"^\d{1,2}/\d{1,2}/\d{4}$"#
            for token in tokens {
                if token.range(of: datePattern, options: .regularExpression) != nil {
                    if let d = convertDate(token), !d.contains("1991") {
                        if !scanDates.contains(d) { scanDates.append(d) }
                    }
                }
            }

            // All non-date, non-pct numbers from this line
            let allNums = tokens.filter { $0.range(of: datePattern, options: .regularExpression) == nil && !$0.hasSuffix("%") }
                .compactMap { Double($0) }.filter { $0 > 0 && $0 < 500 }

            let pcts = tokens.filter { $0.hasSuffix("%") }.compactMap { Double($0.replacingOccurrences(of: "%", with: "")) }

            // Lines with dates also contain total mass values (>100 typically)
            // e.g., "3/6/2026 1/25/2026 ... 120.2 122.3 129.2 130.3 21.0% 25.6 91.5 5.1"
            let hasDates = tokens.contains { $0.range(of: datePattern, options: .regularExpression) != nil }

            if hasDates && !allNums.isEmpty {
                // On the dates line, first batch of numbers before any % are total masses
                // e.g., "dates... 120.2 122.3 129.2 130.3 21.0% 25.6 91.5 5.1"
                // Find position of first % token to split
                let pctPosition = tokens.firstIndex { $0.hasSuffix("%") }
                let numPositions = tokens.enumerated().compactMap { (idx, t) -> (Int, Double)? in
                    guard t.range(of: datePattern, options: .regularExpression) == nil, !t.hasSuffix("%"),
                          let v = Double(t), v > 0, v < 500 else { return nil }
                    return (idx, v)
                }

                if let pctPos = pctPosition {
                    // Numbers before the first % are total masses
                    let masses = numPositions.filter { $0.0 < pctPos }.map(\.1)
                    totalMasses.append(contentsOf: masses)
                    // Numbers after the first % are scan data
                    let scanNums = numPositions.filter { $0.0 > pctPos }.map(\.1)
                    for pct in pcts {
                        pctAndValues.append((pct, scanNums))
                    }
                } else {
                    // No %, all nums are total masses
                    totalMasses.append(contentsOf: allNums)
                }
            } else if !pcts.isEmpty {
                // Pure scan data line: "16.4% 19.8 95.5 4.9" or "25.0% 32.3 91.8 5.1"
                // ALL numbers (regardless of size) are: fatMass, leanMass, bmc
                for pct in pcts {
                    pctAndValues.append((pct, allNums))
                }
            }
        }

        let scanCount = scanDates.count
        guard scanCount > 0 else {
            Log.bodyComp.warning("No scan dates found")
            return []
        }

        Log.bodyComp.info("Dates: \(scanDates), totalMasses: \(totalMasses), pctAndValues: \(pctAndValues.count)")

        // Build scan data
        for i in 0..<scanCount {
            var sd = ScanData(date: scanDates[i])
            sd.totalMassLbs = i < totalMasses.count ? totalMasses[i] : nil
            if i < pctAndValues.count {
                sd.bodyFatPct = pctAndValues[i].pct
                let v = pctAndValues[i].vals
                sd.fatMassLbs = v.count > 0 ? v[0] : nil
                sd.leanMassLbs = v.count > 1 ? v[1] : nil
                sd.bmcLbs = v.count > 2 ? v[2] : nil
            }
            scanDatas.append(sd)
        }

        // Step 2: Regional + muscle balance + supplemental
        let regions = parseRegionalAssessment(lines: lines)
        let muscleBalance = parseMuscleBalance(lines: lines)
        let supplemental = parseSupplemental(lines: lines, scanCount: scanCount)

        var scans: [ParsedScan] = []
        for (i, sd) in scanDatas.enumerated() {
            scans.append(ParsedScan(
                scanDate: sd.date,
                bodyFatPct: sd.bodyFatPct,
                totalMassLbs: sd.totalMassLbs,
                fatMassLbs: sd.fatMassLbs,
                leanMassLbs: sd.leanMassLbs,
                bmcLbs: sd.bmcLbs,
                rmrCalories: i < supplemental.rmr.count ? supplemental.rmr[i] : nil,
                vatMassLbs: i < supplemental.vatMass.count ? supplemental.vatMass[i] : nil,
                vatVolumeIn3: i < supplemental.vatVolume.count ? supplemental.vatVolume[i] : nil,
                agRatio: i < supplemental.agRatio.count ? supplemental.agRatio[i] : nil,
                boneDensityTotal: nil,
                regions: i == 0 ? regions + muscleBalance : []
            ))
        }

        Log.bodyComp.info("Parsed \(scans.count) scans: \(scans.map { "\($0.scanDate): bf=\($0.bodyFatPct ?? -1), fat=\($0.fatMassLbs ?? -1), lean=\($0.leanMassLbs ?? -1)" })")
        return scans
    }

    // MARK: - Regional Assessment

    private static func parseRegionalAssessment(lines: [String]) -> [ParsedRegion] {
        var regions: [ParsedRegion] = []
        // PDFKit format: "Arms 13.4% 16.5 2.2 13.6 0.7"
        let regionNames = ["Arms", "Legs", "Trunk", "Android", "Gynoid", "Total"]

        for line in lines {
            for name in regionNames {
                if line.hasPrefix(name) && line.contains("%") {
                    let tokens = tokenize(line.dropFirst(name.count).description)
                    let pct = tokens.first { $0.hasSuffix("%") }.flatMap { Double($0.replacingOccurrences(of: "%", with: "")) }
                    let nums = tokens.filter { !$0.hasSuffix("%") }.compactMap { Double($0) }
                    if nums.count >= 4 {
                        regions.append(ParsedRegion(
                            name: name.lowercased(), fatPct: pct,
                            totalMassLbs: nums[0], fatMassLbs: nums[1],
                            leanMassLbs: nums[2], bmcLbs: nums[3]
                        ))
                    }
                }
            }
        }
        return regions
    }

    // MARK: - Muscle Balance

    private static func parseMuscleBalance(lines: [String]) -> [ParsedRegion] {
        var regions: [ParsedRegion] = []
        // PDFKit format: "Right Arm 12.6 8.5 1.1 7.1 0.4"
        // Values are: fatPct, totalMass, fatMass, leanMass, BMC (all bare numbers)
        let limbPairs = [("Right Arm", "r_arm"), ("Left Arm", "l_arm"), ("Right Leg", "r_leg"), ("Left Leg", "l_leg")]

        for line in lines {
            for (pdfName, dbName) in limbPairs {
                if line.hasPrefix(pdfName) {
                    let rest = line.dropFirst(pdfName.count).description
                    let nums = tokenize(rest).compactMap { Double($0.replacingOccurrences(of: "%", with: "")) }
                    if nums.count >= 5 {
                        regions.append(ParsedRegion(
                            name: dbName, fatPct: nums[0],
                            totalMassLbs: nums[1], fatMassLbs: nums[2],
                            leanMassLbs: nums[3], bmcLbs: nums[4]
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
    }

    private static func parseSupplemental(lines: [String], scanCount: Int) -> Supplemental {
        var result = Supplemental()

        for line in lines {
            // RMR: "1,311 cal/day 16.2% 18.3% 0.88"
            if line.contains("cal/day") {
                let parts = line.components(separatedBy: "cal/day")
                for part in parts {
                    let cleaned = part.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                    // Extract the number right before "cal/day"
                    let tokens = tokenize(cleaned)
                    if let last = tokens.last, let v = Double(last), v > 500, v < 5000 {
                        result.rmr.append(v)
                    }
                }
                // Also extract A/G ratios from the same line pattern
                let allTokens = tokenize(line)
                for token in allTokens {
                    let cleaned = token.replacingOccurrences(of: "%", with: "")
                    if let v = Double(cleaned), v > 0.3, v < 2.5, !token.hasSuffix("%"), !token.contains("cal") {
                        result.agRatio.append(v)
                    }
                }
            }

            // VAT Mass: "Mass (lbs) 0.56"
            if line.hasPrefix("Mass (lbs)") {
                let nums = tokenize(line).compactMap { Double($0) }.filter { $0 < 10 }
                result.vatMass.append(contentsOf: nums)
            }

            // VAT Volume: "Volume (in3) 16.33"
            if line.hasPrefix("Volume (in3)") || line.contains("Volume (in3)") {
                let nums = tokenize(line).compactMap { Double($0) }.filter { $0 > 5 }
                result.vatVolume.append(contentsOf: nums)
            }
        }

        return result
    }

    // MARK: - Helpers

    private static func tokenize(_ str: String) -> [String] {
        str.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }

    private static func convertDate(_ dateStr: String) -> String? {
        let parts = dateStr.split(separator: "/")
        guard parts.count == 3,
              let m = Int(parts[0]), let d = Int(parts[1]), let y = Int(parts[2]) else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    enum ParseError: LocalizedError {
        case accessDenied, invalidPDF, noDataFound
        var errorDescription: String? {
            switch self {
            case .accessDenied: "Could not access PDF"
            case .invalidPDF: "Not a valid PDF"
            case .noDataFound: "No BodySpec scan data found in PDF"
            }
        }
    }
}
