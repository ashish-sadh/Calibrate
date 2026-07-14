import Testing
import Foundation
@testable import DriftCore

/// Tier 0 — the accuracy net for the deterministic lab parser. Runs the real
/// `LabTextParser` against realistic post-OCR report-text fixtures and asserts
/// precision/recall per report AND aggregate. This is the regression net that
/// did NOT exist before 2026-07-14: the parser lived in the iOS target and its
/// only "test" (`scoreLabReportRegex`) was a stub that never called it, so any
/// format change could silently zero-out extraction with no failing test.
///
/// Expected JSONs use the eval's camelCase IDs (`ldl`, `tsh`) OR canonical
/// snake_case; both are resolved through `BiomarkerCatalogMap.canonicalID`, so
/// the fixtures double as a test of the FM ID-canonicalization map.
struct LabTextParserAccuracyTests {

    struct ExpectedReport: Decodable {
        let labName: String?
        let reportDate: String?
        let biomarkers: [ExpectedMarker]
    }
    struct ExpectedMarker: Decodable {
        let id: String
        let value: Double
        let unit: String?
        let refLow: Double?
        let refHigh: Double?
    }

    struct Fixture {
        let name: String
        let text: String
        let expected: ExpectedReport
    }

    /// Fixtures the parser is EXPECTED to handle deterministically. Loaded from
    /// the flattened test bundle by stem.
    static let stems = ["quest_2025-09-01", "labcorp_2025-08-10", "generic_csv_2025-10-12", "drlal_2026-02-14"]

    static func loadFixtures() throws -> [Fixture] {
        var out: [Fixture] = []
        for stem in stems {
            guard let txtURL = Bundle.module.url(forResource: stem, withExtension: "txt"),
                  let jsonURL = Bundle.module.url(forResource: "\(stem).expected", withExtension: "json") else {
                continue
            }
            let text = try String(contentsOf: txtURL, encoding: .utf8)
            let expected = try JSONDecoder().decode(ExpectedReport.self, from: Data(contentsOf: jsonURL))
            out.append(Fixture(name: stem, text: text, expected: expected))
        }
        return out
    }

    /// Canonicalize an expected marker's ID; expected fixtures are hand-authored
    /// to reference real catalog markers, so a nil here is a fixture bug.
    private func canonicalExpectedID(_ raw: String) -> String {
        BiomarkerCatalogMap.canonicalID(raw) ?? raw
    }

    private func valuesClose(_ a: Double, _ b: Double) -> Bool {
        if a == b { return true }
        let denom = max(abs(a), abs(b), 1e-9)
        return abs(a - b) / denom <= 0.02   // ±2% tolerance for rounding
    }

    // MARK: - Fixtures load

    @Test func fixturesLoad() throws {
        let fixtures = try Self.loadFixtures()
        #expect(fixtures.count == Self.stems.count, "All lab fixtures should load; got \(fixtures.map(\.name))")
        for f in fixtures {
            #expect(!f.expected.biomarkers.isEmpty, "\(f.name) expected set must be non-empty")
        }
    }

    @Test func everyExpectedIDResolvesToCatalog() throws {
        // Guards both the fixtures and the canonicalization map: every ID the
        // fixtures reference must resolve to a real catalog biomarker.
        for f in try Self.loadFixtures() {
            for m in f.expected.biomarkers {
                let canon = BiomarkerCatalogMap.canonicalID(m.id)
                #expect(canon != nil, "\(f.name): expected id '\(m.id)' doesn't resolve to a catalog biomarker")
                if let canon { #expect(BiomarkerKnowledgeBase.byId[canon] != nil) }
            }
        }
    }

    // MARK: - Per-report precision / recall

    @Test func perReportAccuracyMeetsThreshold() throws {
        for f in try Self.loadFixtures() {
            let parsed = LabTextParser.parse(text: f.text)
            let expectedByID = Dictionary(
                f.expected.biomarkers.map { (canonicalExpectedID($0.id), $0) },
                uniquingKeysWith: { a, _ in a })
            let parsedByID = Dictionary(parsed.results.map { ($0.biomarkerId, $0) },
                                        uniquingKeysWith: { a, _ in a })

            var truePositives = 0
            var valueMatches = 0
            for (id, exp) in expectedByID {
                guard let got = parsedByID[id] else { continue }
                truePositives += 1
                if valuesClose(got.value, exp.value) { valueMatches += 1 }
            }
            let recall = Double(truePositives) / Double(expectedByID.count)
            let precision = parsedByID.isEmpty ? 0 : Double(truePositives) / Double(parsedByID.count)
            let valueAccuracy = truePositives == 0 ? 0 : Double(valueMatches) / Double(truePositives)

            // Deterministic parser floors — high because these are exactly the
            // formats it's built for. FM/LLM layers lift the rest at runtime.
            #expect(recall >= 0.90, "\(f.name): recall \(recall) < 0.90 (found \(truePositives)/\(expectedByID.count)); missing \(Set(expectedByID.keys).subtracting(parsedByID.keys).sorted())")
            #expect(precision >= 0.90, "\(f.name): precision \(precision) < 0.90; spurious \(Set(parsedByID.keys).subtracting(expectedByID.keys).sorted())")
            #expect(valueAccuracy >= 0.98, "\(f.name): value accuracy \(valueAccuracy) < 0.98")
        }
    }

    // MARK: - Reference-range extraction (the one-sided fix)

    @Test func oneSidedReferenceRangesAreCaptured() throws {
        // Quest + Dr Lal both carry one-sided ranges (LDL < 100, HDL > 40).
        // Pre-2026-07-14 these were dropped entirely. Assert we now capture the
        // bound and direction for the markers that have them.
        for f in try Self.loadFixtures() {
            let parsed = LabTextParser.parse(text: f.text)
            let parsedByID = Dictionary(parsed.results.map { ($0.biomarkerId, $0) }, uniquingKeysWith: { a, _ in a })
            for exp in f.expected.biomarkers {
                let id = canonicalExpectedID(exp.id)
                guard let got = parsedByID[id] else { continue }
                // One-sided upper bound (e.g. LDL < 100): expected has refHigh, no refLow.
                if let hi = exp.refHigh, exp.refLow == nil {
                    #expect(got.referenceHigh != nil && valuesClose(got.referenceHigh!, hi),
                            "\(f.name)/\(id): expected one-sided high \(hi), got \(String(describing: got.referenceHigh))")
                }
                // One-sided lower bound (e.g. HDL > 40).
                if let lo = exp.refLow, exp.refHigh == nil {
                    #expect(got.referenceLow != nil && valuesClose(got.referenceLow!, lo),
                            "\(f.name)/\(id): expected one-sided low \(lo), got \(String(describing: got.referenceLow))")
                }
            }
        }
    }

    // MARK: - Lab name + date

    @Test func labNameAndDateDetected() throws {
        for f in try Self.loadFixtures() {
            let parsed = LabTextParser.parse(text: f.text)
            if let expName = f.expected.labName {
                // Case-insensitive: the canonical display casing ("Labcorp" vs
                // "LabCorp") is cosmetic and not an accuracy concern.
                #expect(parsed.labName?.lowercased() == expName.lowercased(),
                        "\(f.name): lab '\(String(describing: parsed.labName))' != '\(expName)'")
            }
            if let expDate = f.expected.reportDate {
                #expect(parsed.reportDate == expDate, "\(f.name): date '\(String(describing: parsed.reportDate))' != '\(expDate)'")
            }
        }
    }

    // MARK: - Indian-lab specifics

    @Test func indianLabConventionsExtract() throws {
        let f = try #require(try Self.loadFixtures().first { $0.name == "drlal_2026-02-14" })
        let parsed = LabTextParser.parse(text: f.text)
        let ids = Set(parsed.results.map(\.biomarkerId))
        // SGPT/SGOT → ALT/AST, "Blood Urea" → urea, Total T3/T4, ESR, VLDL.
        for expected in ["alt", "ast", "urea", "total_t3", "total_t4", "esr", "vldl_cholesterol", "direct_bilirubin"] {
            #expect(ids.contains(expected), "Indian fixture should extract \(expected); got \(ids.sorted())")
        }
        // SGPT must map to ALT with the right value, not be dropped.
        if let alt = parsed.results.first(where: { $0.biomarkerId == "alt" }) {
            #expect(alt.value == 42)
        }
    }

    // MARK: - Aggregate accuracy

    @Test func aggregateAccuracyAcrossAllFixtures() throws {
        var totalExpected = 0, totalFound = 0, totalParsed = 0, valueMatches = 0
        for f in try Self.loadFixtures() {
            let parsed = LabTextParser.parse(text: f.text)
            let expectedByID = Dictionary(f.expected.biomarkers.map { (canonicalExpectedID($0.id), $0) }, uniquingKeysWith: { a, _ in a })
            let parsedByID = Dictionary(parsed.results.map { ($0.biomarkerId, $0) }, uniquingKeysWith: { a, _ in a })
            totalExpected += expectedByID.count
            totalParsed += parsedByID.count
            for (id, exp) in expectedByID {
                guard let got = parsedByID[id] else { continue }
                totalFound += 1
                if valuesClose(got.value, exp.value) { valueMatches += 1 }
            }
        }
        let recall = Double(totalFound) / Double(totalExpected)
        let precision = Double(totalFound) / Double(totalParsed)
        #expect(recall >= 0.92, "aggregate recall \(recall) (\(totalFound)/\(totalExpected))")
        #expect(precision >= 0.92, "aggregate precision \(precision) (\(totalFound)/\(totalParsed))")
        #expect(Double(valueMatches) / Double(totalFound) >= 0.98, "aggregate value accuracy")
    }
}
