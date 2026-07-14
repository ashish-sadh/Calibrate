import Testing
import Foundation
@testable import DriftCore

/// Tier 0 — the unit-normalization surface (`normalize` / `normalizeResult`)
/// plus the parser fixes for international + Indian lab formats. Before
/// 2026-07-14 the accuracy suite asserted only the raw parsed value and NEVER
/// called normalize(), so SI-unit conversions (the exact case Indian/intl
/// reports hit) were completely untested.
struct BiomarkerNormalizationTests {

    private func approx(_ a: Double, _ b: Double, tol: Double = 0.02) -> Bool {
        abs(a - b) / max(abs(b), 1e-9) <= tol
    }

    // MARK: - Micro-sign (the highest-leverage fix)

    @Test func microSignUnitsConvert() {
        // "Creatinine 80 µmol/L" must NOT be stored as 80 mg/dL. µ (U+00B5).
        let (v, u) = BiomarkerKnowledgeBase.normalize(biomarkerId: "creatinine", value: 80, fromUnit: "\u{00B5}mol/L")
        #expect(u == "mg/dL")
        #expect(approx(v, 80 / 88.42))   // ≈ 0.905
        // Greek mu (U+03BC) too.
        let (v2, _) = BiomarkerKnowledgeBase.normalize(biomarkerId: "uric_acid", value: 420, fromUnit: "\u{03BC}mol/L")
        #expect(approx(v2, 420 / 59.48))  // ≈ 7.06
    }

    @Test func parserNormalizesMicroSignInText() {
        let text = "Creatinine  80  \u{00B5}mol/L  60 - 110"
        let parsed = LabTextParser.parse(text: text)
        let cr = parsed.results.first { $0.biomarkerId == "creatinine" }
        #expect(cr?.unit == "umol/L")   // micro-sign folded to ASCII so the unit is recognized
    }

    // MARK: - SI conversions that were missing

    @Test func thyroidFreeHormonesPmolConvert() {
        let (ft4, u4) = BiomarkerKnowledgeBase.normalize(biomarkerId: "free_t4", value: 15, fromUnit: "pmol/L")
        #expect(u4 == "ng/dL")
        #expect(approx(ft4, 15 * 0.0777))   // ≈ 1.17
        let (ft3, u3) = BiomarkerKnowledgeBase.normalize(biomarkerId: "free_t3", value: 5, fromUnit: "pmol/L")
        #expect(u3 == "pg/mL")
        #expect(approx(ft3, 5 * 0.651))     // ≈ 3.26
    }

    @Test func cholesterolAndGlucoseMmolConvert() {
        let (chol, _) = BiomarkerKnowledgeBase.normalize(biomarkerId: "total_cholesterol", value: 5.0, fromUnit: "mmol/L")
        #expect(approx(chol, 5.0 * 38.67))
        let (glu, _) = BiomarkerKnowledgeBase.normalize(biomarkerId: "glucose", value: 5.5, fromUnit: "mmol/L")
        #expect(approx(glu, 5.5 * 18.018))
    }

    @Test func wbcAbsoluteCountConvertsToKPerUL() {
        let (wbc, u) = BiomarkerKnowledgeBase.normalize(biomarkerId: "wbc", value: 7200, fromUnit: "cells/uL")
        #expect(u == "K/uL")
        #expect(approx(wbc, 7.2))
        // A K/uL value passes through unchanged.
        let (wbc2, _) = BiomarkerKnowledgeBase.normalize(biomarkerId: "wbc", value: 7.2, fromUnit: "K/uL")
        #expect(wbc2 == 7.2)
    }

    // MARK: - Reference bounds convert with the value (C5)

    @Test func referenceBoundsConvertWithValue() {
        // Glucose 5.5 mmol/L (3.9–5.6) → value AND range in mg/dL.
        let r = BiomarkerKnowledgeBase.normalizeResult(
            biomarkerId: "glucose", value: 5.5, fromUnit: "mmol/L", referenceLow: 3.9, referenceHigh: 5.6)
        #expect(approx(r.value, 99.1))
        #expect(approx(r.referenceLow!, 3.9 * 18.018))
        #expect(approx(r.referenceHigh!, 5.6 * 18.018))
    }

    @Test func alreadyStandardLeavesReferenceUntouched() {
        let r = BiomarkerKnowledgeBase.normalizeResult(
            biomarkerId: "glucose", value: 99, fromUnit: "mg/dL", referenceLow: 70, referenceHigh: 99)
        #expect(r.referenceLow == 70 && r.referenceHigh == 99)
    }

    // MARK: - WBC absolute-count value guard (C1)

    @Test func elevatedAbsoluteWbcNotDroppedForRangeLow() {
        let text = "Total Leukocyte Count   12500 cells/uL   4000 - 10000"
        let parsed = LabTextParser.parse(text: text)
        let wbc = parsed.results.first { $0.biomarkerId == "wbc" }
        #expect(wbc?.value == 12500)   // not 4000 (the range low)
    }

    // MARK: - Indian glucose aliases (H1)

    @Test func indianGlucoseSynonymsExtract() {
        for line in ["Random Blood Sugar   110 mg/dL   70 - 140",
                     "FBS   92 mg/dL   70 - 99",
                     "Post Prandial Blood Sugar   130 mg/dL"] {
            let parsed = LabTextParser.parse(text: line)
            #expect(parsed.results.contains { $0.biomarkerId == "glucose" }, "should extract glucose from: \(line)")
        }
    }

    @Test func vitDShorthandExtracts() {
        let parsed = LabTextParser.parse(text: "Vit D3   28 ng/mL   30 - 100")
        #expect(parsed.results.contains { $0.biomarkerId == "vitamin_d" })
    }

    @Test func dottedCholesterolPrefixExtracts() {
        let parsed = LabTextParser.parse(text: "T. Cholesterol   185 mg/dL   < 200")
        #expect(parsed.results.contains { $0.biomarkerId == "total_cholesterol" })
    }

    // MARK: - Word-boundary guards (M1, M2)

    @Test func hdlDoesNotMatchNonHdlLine() {
        // Only a Non-HDL line present → HDL must NOT steal its value.
        let parsed = LabTextParser.parse(text: "Non-HDL Cholesterol   130 mg/dL   < 130")
        #expect(parsed.results.first { $0.biomarkerId == "hdl_cholesterol" } == nil)
        #expect(parsed.results.contains { $0.biomarkerId == "non_hdl_cholesterol" })
    }

    @Test func ironDoesNotMatchIronSaturation() {
        let parsed = LabTextParser.parse(text: "Iron Saturation   25 %   20 - 50")
        // Should classify as iron_saturation, not serum iron = 25.
        #expect(parsed.results.first { $0.biomarkerId == "iron" } == nil)
    }

    // MARK: - Indian DD/MM date (H2)

    @Test func indianLabDatePrefersDayFirst() {
        let text = """
        Dr Lal PathLabs
        Sample Collected On: 05/06/2026
        Haemoglobin  14.8 g/dL  13.0 - 17.0
        """
        let parsed = LabTextParser.parse(text: text)
        #expect(parsed.labName == "Dr Lal PathLabs")
        #expect(parsed.reportDate == "2026-06-05")   // 5 June, not 6 May
    }

    @Test func usLabDateStaysMonthFirst() {
        let text = """
        Quest Diagnostics
        Specimen Drawn: 05/06/2026
        Glucose  Final  92 mg/dL  (65-99)
        """
        let parsed = LabTextParser.parse(text: text)
        #expect(parsed.reportDate == "2026-05-06")   // May 6, US order
    }
}
