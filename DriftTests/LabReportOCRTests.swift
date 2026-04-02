import Testing
@testable import Drift

// MARK: - Quest Diagnostics Report (anonymized from real PDF)

private let questReportText = """
Jane Doe Quest Result 12/19/2025
PATIENT INFORMATION:
Jane Doe
Phone (H): 5551234567
DOB: 01/15/1990
Source: Quest
Collection Date: 12/12/2025 05:05 PM UTC
Gender: Male Age: 35
Patient ID: 99900001
Test In Range Out Of Range Reference Range Previous Result Date Lab
FASTING: YES
IRON, TIBC AND FERRITIN PANEL Collected: 12/12/2025 05:05 PM UTC Received: 12/12/2025 05:05 PM UTC
 IRON, TOTAL 114 50-180 mcg/dL 137.0 10/10/2025 UL
 IRON BINDING 370 250-425 mcg/dL 364.0 10/10/2025 UL
 CAPACITY (calc)
 % SATURATION 31 20-48 % (calc) 38.0 10/10/2025 UL
 FERRITIN 32 L 38-380 ng/mL 71.0 10/10/2025 UL
LIPID PANEL, STANDARD Collected: 12/12/2025 05:05 PM UTC Received: 12/12/2025 05:05 PM UTC
 CHOLESTEROL, TOTAL 168 <200 mg/dL 181.0 10/10/2025 UL
 HDL CHOLESTEROL 57 > OR = 40 mg/dL 41.0 10/10/2025 UL
 TRIGLYCERIDES 49 <150 mg/dL 227.0 H 10/10/2025 UL
 LDL-CHOLESTEROL 97 mg/dL (calc) 106.0 H 10/10/2025 UL
NON HDL 111 <130 mg/dL (calc) 140.0 H 10/10/2025 UL
CHOLESTEROL
LIPOPROTEIN (a) Collected: 12/12/2025 05:05 PM UTC Received: 12/12/2025 05:05 PM UTC
 LIPOPROTEIN (a) 59 nmol/L 52.0 10/10/2025 EN
COMPREHENSIVE METABOLIC PANEL Collected: 12/12/2025 05:05 PM UTC Received: 12/12/2025 05:05 PM
 GLUCOSE 89 65-99 mg/dL 73.0 10/10/2025 UL
UREA NITROGEN 15 7-25 mg/dL 16.0 10/10/2025 UL
(BUN)
CREATININE 0.89 0.60-1.26 mg/dL 1.02 10/10/2025 UL
EGFR 115 > OR = 60 mL/min/1.73m2 100.0 10/10/2025 UL
SODIUM 136 135-146 mmol/L 137.0 10/10/2025 UL
POTASSIUM 4.3 3.5-5.3 mmol/L 4.4 10/10/2025 UL
CHLORIDE 101 98-110 mmol/L 105.0 10/10/2025 UL
CARBON DIOXIDE 28 20-32 mmol/L 29.0 10/10/2025 UL
CALCIUM 9.3 8.6-10.3 mg/dL 9.2 10/10/2025 UL
PROTEIN, TOTAL 7.3 6.1-8.1 g/dL 7.3 10/10/2025 UL
ALBUMIN 4.6 3.6-5.1 g/dL 4.4 10/10/2025 UL
GLOBULIN 2.7 1.9-3.7 g/dL (calc) 2.9 10/10/2025 UL
ALBUMIN/GLOBULIN 1.7 1.0-2.5 (calc) 1.5 10/10/2025 UL
RATIO
BILIRUBIN, TOTAL 0.5 0.2-1.2 mg/dL 0.5 10/10/2025 UL
ALKALINE 100 36-130 U/L 93.0 10/10/2025 UL
PHOSPHATASE
AST 21 10-40 U/L 20.0 10/10/2025 UL
ALT 21 9-46 U/L 17.0 10/10/2025 UL
TESTOSTERONE, FREE (DIALYSIS), TOTAL (MS) AND SEX HORMONE BINDING GLOBULIN Collected: 12/12/2025
 TESTOSTERONE, TOTAL, MS 656 250-1100 ng/dL 503.0 10/10/2025 EZ
 TESTOSTERONE, FREE 106.9 35.0-155.0 pg/mL 96.1 10/10/2025 EZ
SEX HORMONE BINDING GLOBULIN 36 10-50 nmol/L 29.0 10/10/2025 EZ
 WHITE BLOOD CELL COUNT 4.4 3.8-10.8 Thousand/uL 6.2 10/10/2025 UL
 RED BLOOD CELL COUNT 5.27 4.20-5.80 Million/uL 5.52 10/10/2025 UL
 HEMOGLOBIN 15.6 13.2-17.1 g/dL 16.6 10/10/2025 UL
 HEMATOCRIT 47.1 39.4-51.1 % 49.7 10/10/2025 UL
 MCV 89.4 81.4-101.7 fL 90.0 10/10/2025 UL
 MCH 29.6 27.0-33.0 pg 30.1 10/10/2025 UL
 MCHC 33.1 31.6-35.4 g/dL 33.4 10/10/2025 UL
 RDW 14.7 11.0-15.0 % 13.8 10/10/2025 UL
 PLATELET COUNT 246 140-400 Thousand/uL 264.0 10/10/2025 UL
 ABSOLUTE NEUTROPHILS 2548 1500-7800 cells/uL 3577.0 10/10/2025 UL
 ABSOLUTE LYMPHOCYTES 1188 850-3900 cells/uL 1810.0 10/10/2025 UL
 ABSOLUTE MONOCYTES 453 200-950 cells/uL 533.0 10/10/2025 UL
 ABSOLUTE EOSINOPHILS 180 15-500 cells/uL 242.0 10/10/2025 UL
 ABSOLUTE BASOPHILS 31 0-200 cells/uL 37.0 10/10/2025 UL
NEUTROPHILS 57.9 % 57.7 10/10/2025 UL
LYMPHOCYTES 27.0 % 29.2 10/10/2025 UL
MONOCYTES 10.3 % 8.6 10/10/2025 UL
EOSINOPHILS 4.1 % 3.9 10/10/2025 UL
 BASOPHILS 0.7 % 0.6 10/10/2025 UL
HS CRP Collected: 12/12/2025 05:05 PM UTC Received: 12/12/2025 05:05 PM UTC
 HS CRP 0.4 mg/L 0.9 10/10/2025 UL
HOMOCYSTEINE Collected: 12/12/2025 05:05 PM UTC Received: 12/12/2025 05:05 PM UTC
 HOMOCYSTEINE 7.1 < or = 13.5 umol/L 8.1 10/10/2025 UL
DHEA SULFATE Collected: 12/12/2025 05:05 PM UTC Received: 12/12/2025 05:05 PM UTC
 DHEA SULFATE 183 93-415 mcg/dL 177.0 10/10/2025 EN
INSULIN Collected: 12/12/2025 05:05 PM UTC Received: 12/12/2025 05:05 PM UTC
 INSULIN 4.8 uIU/mL 24.4 H 10/10/2025 EN
CORTISOL, TOTAL Collected: 12/12/2025 05:05 PM UTC Received: 12/12/2025 05:05 PM UTC
 CORTISOL, TOTAL 11.2 mcg/dL 6.9 10/10/2025 UL
TSH Collected: 12/12/2025 05:05 PM UTC Received: 12/12/2025 05:05 PM UTC
 TSH 1.71 0.40-4.50 mIU/L 1.42 10/10/2025 UL
ESTRADIOL Collected: 12/12/2025 05:05 PM UTC Received: 12/12/2025 05:05 PM UTC
 ESTRADIOL 40 H < OR = 39 pg/mL 28.0 10/10/2025 UL
APOLIPOPROTEIN B Collected: 12/12/2025 05:05 PM UTC Received: 12/12/2025 05:05 PM UTC
 APOLIPOPROTEIN B 85 mg/dL 96.0 H 10/10/2025 EN
HEMOGLOBIN A1c Collected: 12/12/2025 05:05 PM UTC Received: 12/12/2025 05:05 PM UTC
 HEMOGLOBIN A1c 5.3 <5.7 % 5.4 10/10/2025 UL
"""

// MARK: - LabCorp Report (anonymized from real PDF)

private let labcorpReportText = """
DOE, JANE Overall Report Status: FINAL
(SN: 10000000000) Received on 12/05/2021
Lab Report from LabCorp
Specimen Number Patient ID Control Number Account Number
10000000000 100000001 1000001 00000001
Date/Time Date Entered Date/Time
Collected Reported
2021-12-02 2021-12-02 2021-12-05
06:21:00 PST 21:00:00 PST 04:05:00 PST
TESTS RESULTS FLAG UNITS REFERENCE INTERVAL LAB
CBC With Differential/Platelet
  WBC 6.0 x10E3/uL 3.4-10.8 01
  RBC 5.30 x10E6/uL 4.14-5.80 01
  Hemoglobin 15.9 g/dL 13.0-17.7 01
  Hematocrit 47.3 % 37.5-51.0 01
  MCV 89 fL 79-97 01
  MCH 30.0 pg 26.6-33.0 01
  MCHC 33.6 g/dL 31.5-35.7 01
  RDW 13.8 % 11.6-15.4 01
  Platelets 270 x10E3/uL 150-450 01
  Neutrophils 58 % Not Estab. 01
  Lymphs 30 % Not Estab. 01
  Monocytes 8 % Not Estab. 01
  Eos 4 % Not Estab. 01
  Basos 0 % Not Estab. 01
  Neutrophils (Absolute) 3.5 x10E3/uL 1.4-7.0 01
  Lymphs (Absolute) 1.8 x10E3/uL 0.7-3.1 01
  Monocytes(Absolute) 0.5 x10E3/uL 0.1-0.9 01
  Eos (Absolute) 0.2 x10E3/uL 0.0-0.4 01
  Baso (Absolute) 0.0 x10E3/uL 0.0-0.2 01
Comp. Metabolic Panel (14)
  Glucose 92 mg/dL 65-99 01
  BUN 12 mg/dL 6-20 01
  Creatinine 0.91 mg/dL 0.76-1.27 01
  eGFR If NonAfricn Am 113 mL/min/1.73 >59 01
  Sodium 140 mmol/L 134-144 01
  Potassium 4.2 mmol/L 3.5-5.2 01
  Chloride 103 mmol/L 96-106 01
  Carbon Dioxide, Total 24 mmol/L 20-29 01
  Calcium 9.3 mg/dL 8.7-10.2 01
  Protein, Total 7.1 g/dL 6.0-8.5 01
  Albumin 4.2 g/dL 4.1-5.2 01
  Globulin, Total 2.9 g/dL 1.5-4.5 01
  A/G Ratio 1.4 1.2-2.2 01
  Bilirubin, Total 0.4 mg/dL 0.0-1.2 01
  Alkaline Phosphatase 102 IU/L 44-121 01
  AST (SGOT) 20 IU/L 0-40 01
  ALT (SGPT) 22 IU/L 0-44 01
Lipid Panel
  Cholesterol, Total 183 mg/dL 100-199 01
  Triglycerides 54 mg/dL 0-149 01
  HDL Cholesterol 45 mg/dL >39 01
  LDL Chol Calc (NIH) 128 High mg/dL 0-99 01
Hemoglobin A1c
  Hemoglobin A1c 5.9 High % 4.8-5.6 01
"""

// MARK: - Tests

@Test func questLabDetected() {
    let output = LabReportOCR.parseLabReport(text: questReportText)
    #expect(output.labName == "Quest Diagnostics")
}

@Test func questDateDetected() {
    let output = LabReportOCR.parseLabReport(text: questReportText)
    #expect(output.reportDate == "2025-12-12")
}

@Test func labcorpLabDetected() {
    let output = LabReportOCR.parseLabReport(text: labcorpReportText)
    #expect(output.labName == "Labcorp")
}

@Test func labcorpDateDetected() {
    let output = LabReportOCR.parseLabReport(text: labcorpReportText)
    // LabCorp's "Received on 12/05/2021" is the most prominent date; collected date is split across lines
    #expect(output.reportDate == "2021-12-05" || output.reportDate == "2021-12-02")
}

@Test func questExtractsMinimum30Markers() {
    let output = LabReportOCR.parseLabReport(text: questReportText)
    #expect(output.results.count >= 30, "Expected >=30 markers, got \(output.results.count)")
}

@Test func labcorpExtractsMinimum20Markers() {
    let output = LabReportOCR.parseLabReport(text: labcorpReportText)
    #expect(output.results.count >= 20, "Expected >=20 markers, got \(output.results.count)")
}

// MARK: - Quest Value Accuracy

@Test func questCholesterol() {
    let r = findResult("total_cholesterol", in: questReportText)
    #expect(r?.value == 168)
}

@Test func questHDL() {
    let r = findResult("hdl_cholesterol", in: questReportText)
    #expect(r?.value == 57)
}

@Test func questTriglycerides() {
    let r = findResult("triglycerides", in: questReportText)
    #expect(r?.value == 49)
}

@Test func questLDL() {
    let r = findResult("ldl_cholesterol", in: questReportText)
    #expect(r?.value == 97)
}

@Test func questGlucose() {
    let r = findResult("glucose", in: questReportText)
    #expect(r?.value == 89)
}

@Test func questBUN() {
    let r = findResult("bun", in: questReportText)
    #expect(r?.value == 15)
}

@Test func questCreatinine() {
    let r = findResult("creatinine", in: questReportText)
    #expect(r?.value == 0.89)
}

@Test func questSodium() {
    let r = findResult("sodium", in: questReportText)
    #expect(r?.value == 136)
}

@Test func questCalcium() {
    let r = findResult("calcium", in: questReportText)
    #expect(r?.value == 9.3)
}

@Test func questAlbumin() {
    let r = findResult("albumin", in: questReportText)
    #expect(r?.value == 4.6)
}

@Test func questAST() {
    let r = findResult("ast", in: questReportText)
    #expect(r?.value == 21)
}

@Test func questALT() {
    let r = findResult("alt", in: questReportText)
    #expect(r?.value == 21)
}

@Test func questTestosterone() {
    let r = findResult("testosterone_total", in: questReportText)
    #expect(r?.value == 656)
}

@Test func questFreeTestosterone() {
    let r = findResult("free_testosterone", in: questReportText)
    #expect(r?.value == 106.9)
}

@Test func questHemoglobin() {
    let r = findResult("hemoglobin", in: questReportText)
    #expect(r?.value == 15.6)
}

@Test func questHematocrit() {
    let r = findResult("hematocrit", in: questReportText)
    #expect(r?.value == 47.1)
}

@Test func questPlatelets() {
    let r = findResult("platelets", in: questReportText)
    #expect(r?.value == 246)
}

@Test func questWBC() {
    let r = findResult("wbc", in: questReportText)
    #expect(r?.value == 4.4)
}

@Test func questHsCRP() {
    let r = findResult("hs_crp", in: questReportText)
    #expect(r?.value == 0.4)
}

@Test func questHomocysteine() {
    let r = findResult("homocysteine", in: questReportText)
    #expect(r?.value == 7.1)
}

@Test func questInsulin() {
    let r = findResult("insulin", in: questReportText)
    #expect(r?.value == 4.8)
}

@Test func questTSH() {
    let r = findResult("thyroid_tsh", in: questReportText)
    #expect(r?.value == 1.71)
}

@Test func questEstradiol() {
    let r = findResult("estradiol", in: questReportText)
    #expect(r?.value == 40)
}

@Test func questHbA1c() {
    let r = findResult("hba1c", in: questReportText)
    #expect(r?.value == 5.3)
}

@Test func questApoB() {
    let r = findResult("apolipoprotein_b", in: questReportText)
    #expect(r?.value == 85)
}

@Test func questFerritin() {
    let r = findResult("ferritin", in: questReportText)
    #expect(r?.value == 32)
}

@Test func questLipoproteinA() {
    let r = findResult("lipoprotein_a", in: questReportText)
    #expect(r?.value == 59)
}

@Test func questIronSaturation() {
    let r = findResult("iron_saturation", in: questReportText)
    #expect(r?.value == 31)
}

@Test func questCortisol() {
    let r = findResult("cortisol", in: questReportText)
    #expect(r?.value == 11.2)
}

@Test func questDHEAS() {
    let r = findResult("dhea_s", in: questReportText)
    #expect(r?.value == 183)
}

// MARK: - LabCorp Value Accuracy

@Test func labcorpGlucose() {
    let r = findResult("glucose", in: labcorpReportText)
    #expect(r?.value == 92)
}

@Test func labcorpCholesterol() {
    let r = findResult("total_cholesterol", in: labcorpReportText)
    #expect(r?.value == 183)
}

@Test func labcorpHDL() {
    let r = findResult("hdl_cholesterol", in: labcorpReportText)
    #expect(r?.value == 45)
}

@Test func labcorpLDL() {
    let r = findResult("ldl_cholesterol", in: labcorpReportText)
    #expect(r?.value == 128)
}

@Test func labcorpHemoglobin() {
    let r = findResult("hemoglobin", in: labcorpReportText)
    #expect(r?.value == 15.9)
}

@Test func labcorpHbA1c() {
    let r = findResult("hba1c", in: labcorpReportText)
    #expect(r?.value == 5.9)
}

@Test func labcorpCreatinine() {
    let r = findResult("creatinine", in: labcorpReportText)
    #expect(r?.value == 0.91)
}

@Test func labcorpWBC() {
    let r = findResult("wbc", in: labcorpReportText)
    #expect(r?.value == 6.0)
}

@Test func labcorpALT() {
    let r = findResult("alt", in: labcorpReportText)
    #expect(r?.value == 22)
}

@Test func labcorpAST() {
    let r = findResult("ast", in: labcorpReportText)
    #expect(r?.value == 20)
}

@Test func labcorpAlbumin() {
    let r = findResult("albumin", in: labcorpReportText)
    #expect(r?.value == 4.2)
}

// MARK: - Quest: Remaining Untested Biomarkers

@Test func questIron() { #expect(findResult("iron", in: questReportText)?.value == 114) }
@Test func questTIBC() { #expect(findResult("tibc", in: questReportText)?.value == 370) }
@Test func questNonHDL() { #expect(findResult("non_hdl_cholesterol", in: questReportText)?.value == 111) }
@Test func questSHBG() { #expect(findResult("shbg", in: questReportText)?.value == 36) }
@Test func questRBC() { #expect(findResult("rbc", in: questReportText)?.value == 5.27) }
@Test func questMCV() { #expect(findResult("mcv", in: questReportText)?.value == 89.4) }
@Test func questMCH() { #expect(findResult("mch", in: questReportText)?.value == 29.6) }
@Test func questMCHC() { #expect(findResult("mchc", in: questReportText)?.value == 33.1) }
@Test func questRDW() { #expect(findResult("rdw", in: questReportText)?.value == 14.7) }
@Test func questEGFR() { #expect(findResult("egfr", in: questReportText)?.value == 115) }
@Test func questPotassium() { #expect(findResult("potassium", in: questReportText)?.value == 4.3) }
@Test func questChloride() { #expect(findResult("chloride", in: questReportText)?.value == 101) }
@Test func questCO2() { #expect(findResult("co2", in: questReportText)?.value == 28) }
@Test func questGlobulin() { #expect(findResult("globulin", in: questReportText)?.value == 2.7) }
@Test func questAGRatio() { #expect(findResult("ag_ratio", in: questReportText)?.value == 1.7) }
@Test func questTotalProtein() { #expect(findResult("total_protein", in: questReportText)?.value == 7.3) }
@Test func questTotalBilirubin() { #expect(findResult("total_bilirubin", in: questReportText)?.value == 0.5) }
@Test func questALP() { #expect(findResult("alp", in: questReportText)?.value == 100) }

// MARK: - Quest: WBC Differentials (% vs Absolute Disambiguation)

@Test func questNeutrophilPct() { #expect(findResult("neutrophil_pct", in: questReportText)?.value == 57.9) }
@Test func questLymphocytePct() { #expect(findResult("lymphocyte_pct", in: questReportText)?.value == 27.0) }
@Test func questMonocytePct() { #expect(findResult("monocyte_pct", in: questReportText)?.value == 10.3) }
@Test func questEosinophilPct() { #expect(findResult("eosinophil_pct", in: questReportText)?.value == 4.1) }
@Test func questBasophilPct() { #expect(findResult("basophil_pct", in: questReportText)?.value == 0.7) }
@Test func questNeutrophilsAbs() { #expect(findResult("neutrophils", in: questReportText)?.value == 2548) }
@Test func questLymphocytesAbs() { #expect(findResult("lymphocytes", in: questReportText)?.value == 1188) }
@Test func questMonocytesAbs() { #expect(findResult("monocytes", in: questReportText)?.value == 453) }
@Test func questEosinophilsAbs() { #expect(findResult("eosinophils", in: questReportText)?.value == 180) }
@Test func questBasophilsAbs() { #expect(findResult("basophils", in: questReportText)?.value == 31) }

// MARK: - LabCorp: Remaining Untested Biomarkers

@Test func labcorpRBC() { #expect(findResult("rbc", in: labcorpReportText)?.value == 5.30) }
@Test func labcorpMCV() { #expect(findResult("mcv", in: labcorpReportText)?.value == 89) }
@Test func labcorpMCH() { #expect(findResult("mch", in: labcorpReportText)?.value == 30.0) }
@Test func labcorpMCHC() { #expect(findResult("mchc", in: labcorpReportText)?.value == 33.6) }
@Test func labcorpRDW() { #expect(findResult("rdw", in: labcorpReportText)?.value == 13.8) }
@Test func labcorpPlatelets() { #expect(findResult("platelets", in: labcorpReportText)?.value == 270) }
@Test func labcorpALP() { #expect(findResult("alp", in: labcorpReportText)?.value == 102) }
@Test func labcorpTotalProtein() { #expect(findResult("total_protein", in: labcorpReportText)?.value == 7.1) }
@Test func labcorpTotalBilirubin() { #expect(findResult("total_bilirubin", in: labcorpReportText)?.value == 0.4) }
@Test func labcorpGlobulin() { #expect(findResult("globulin", in: labcorpReportText)?.value == 2.9) }
@Test func labcorpAGRatio() { #expect(findResult("ag_ratio", in: labcorpReportText)?.value == 1.4) }
@Test func labcorpPotassium() { #expect(findResult("potassium", in: labcorpReportText)?.value == 4.2) }
@Test func labcorpChloride() { #expect(findResult("chloride", in: labcorpReportText)?.value == 103) }
@Test func labcorpCO2() { #expect(findResult("co2", in: labcorpReportText)?.value == 24) }
@Test func labcorpSodium() { #expect(findResult("sodium", in: labcorpReportText)?.value == 140) }
@Test func labcorpTriglycerides() { #expect(findResult("triglycerides", in: labcorpReportText)?.value == 54) }
@Test func labcorpBUN() { #expect(findResult("bun", in: labcorpReportText)?.value == 12) }
@Test func labcorpEGFR() { #expect(findResult("egfr", in: labcorpReportText)?.value == 113) }
@Test func labcorpCalcium() { #expect(findResult("calcium", in: labcorpReportText)?.value == 9.3) }

// MARK: - Edge Cases

private let edgeCaseText = """
VITAMIN D,25-OH,TOTAL,IA 49 30-100 ng/mL 58.0 10/10/2025 UL
FERRITIN 1,234 ng/mL 38-380 UL
HCV Ab <0.1 s/co ratio 0.0-0.9 01
"""

@Test func vitaminD25OHExtractsCorrectValue() {
    let r = findResult("vitamin_d", in: edgeCaseText)
    #expect(r?.value == 49, "Should extract 49, not 25 from '25-OH'")
}

@Test func commaGroupedNumberParsed() {
    let r = findResult("ferritin", in: edgeCaseText)
    #expect(r?.value == 1234)
}

@Test func lessThanPrefixedValueParsed() {
    // <0.1 should parse — we don't track HCV but this tests the < handling
    let text = "HS CRP <0.3 mg/L 0.9 10/10/2025 UL"
    let r = findResult("hs_crp", in: text)
    #expect(r?.value == 0.3)
}

@Test func emptyInputReturnsEmpty() {
    let output = LabReportOCR.parseLabReport(text: "")
    #expect(output.results.isEmpty)
}

@Test func garbageInputReturnsEmpty() {
    let output = LabReportOCR.parseLabReport(text: "Hello world this is not a lab report at all.")
    #expect(output.results.isEmpty)
}

@Test func referenceRangeExtracted() {
    let r = findResult("glucose", in: questReportText)
    #expect(r?.referenceLow == 65)
    #expect(r?.referenceHigh == 99)
}

@Test func mergeMultiLineNames() {
    let text = """
    ALKALINE
    PHOSPHATASE 100 36-130 U/L 93.0 10/10/2025 UL
    """
    let r = findResult("alp", in: text)
    #expect(r?.value == 100)
}

@Test func mergeTestosteroneTotal() {
    let text = """
    TESTOSTERONE,
    TOTAL, MS 656 250-1100 ng/dL 503.0 10/10/2025 EZ
    """
    let r = findResult("testosterone_total", in: text)
    #expect(r?.value == 656)
}

// MARK: - WBC Disambiguation: Both % and Absolute on Same Report

@Test func wbcDisambiguationBothPresent() {
    let text = """
    ABSOLUTE NEUTROPHILS 2548 1500-7800 cells/uL
    ABSOLUTE LYMPHOCYTES 1188 850-3900 cells/uL
    ABSOLUTE MONOCYTES 453 200-950 cells/uL
    ABSOLUTE EOSINOPHILS 180 15-500 cells/uL
    ABSOLUTE BASOPHILS 31 0-200 cells/uL
    NEUTROPHILS 57.9 % 57.7 UL
    LYMPHOCYTES 27.0 % 29.2 UL
    MONOCYTES 10.3 % 8.6 UL
    EOSINOPHILS 4.1 % 3.9 UL
    BASOPHILS 0.7 % 0.6 UL
    """
    let output = LabReportOCR.parseLabReport(text: text)
    let byId = Dictionary(uniqueKeysWithValues: output.results.map { ($0.biomarkerId, $0.value) })
    // Absolute values
    #expect(byId["neutrophils"] == 2548)
    #expect(byId["lymphocytes"] == 1188)
    #expect(byId["monocytes"] == 453)
    #expect(byId["eosinophils"] == 180)
    #expect(byId["basophils"] == 31)
    // Percentage values
    #expect(byId["neutrophil_pct"] == 57.9)
    #expect(byId["lymphocyte_pct"] == 27.0)
    #expect(byId["monocyte_pct"] == 10.3)
    #expect(byId["eosinophil_pct"] == 4.1)
    #expect(byId["basophil_pct"] == 0.7)
}

@Test func wbcPercentOnlyReport() {
    let text = """
    Neutrophils 58 % Not Estab. 01
    Lymphs 30 % Not Estab. 01
    Monocytes 8 % Not Estab. 01
    Eos 4 % Not Estab. 01
    Basos 0 % Not Estab. 01
    """
    let output = LabReportOCR.parseLabReport(text: text)
    let byId = Dictionary(uniqueKeysWithValues: output.results.map { ($0.biomarkerId, $0.value) })
    #expect(byId["neutrophil_pct"] == 58)
    #expect(byId["lymphocyte_pct"] == 30)
    #expect(byId["eosinophil_pct"] == 4)
    #expect(byId["basophil_pct"] == 0)
    // Absolute forms should NOT be present
    #expect(byId["neutrophils"] == nil)
    #expect(byId["lymphocytes"] == nil)
}

// MARK: - Synthetic Fixture Tests

@Test func syntheticVitaminD() {
    let text = "VITAMIN D, 25-HYDROXY 45.0 30-100 ng/mL"
    let r = findResult("vitamin_d", in: text)
    #expect(r?.value == 45.0)
}

@Test func syntheticFolate() {
    let text = "FOLATE 15.2 >3.0 ng/mL"
    let r = findResult("folate", in: text)
    #expect(r?.value == 15.2)
}

@Test func syntheticVitaminB12() {
    let text = "VITAMIN B12 650 232-1245 pg/mL"
    let r = findResult("vitamin_b12", in: text)
    #expect(r?.value == 650)
}

@Test func syntheticUricAcid() {
    let text = "URIC ACID 5.8 3.7-8.6 mg/dL"
    let r = findResult("uric_acid", in: text)
    #expect(r?.value == 5.8)
}

@Test func syntheticGGT() {
    let text = "GGT 22 9-48 U/L"
    let r = findResult("ggt", in: text)
    #expect(r?.value == 22)
}

// MARK: - Date Parsing Tests

@Test func dateParsingMMDDYYYY() {
    let text = "Collection Date: 03/15/2026\nGLUCOSE 89 mg/dL"
    let output = LabReportOCR.parseLabReport(text: text)
    #expect(output.reportDate == "2026-03-15")
}

@Test func dateParsingYYYYMMDD() {
    let text = "Date: 2026-03-15\nGLUCOSE 89 mg/dL"
    let output = LabReportOCR.parseLabReport(text: text)
    #expect(output.reportDate == "2026-03-15")
}

@Test func dateParsingMonthNameDDYYYY() {
    let text = "Collection Date: Mar 15, 2026\nGLUCOSE 89 mg/dL"
    let output = LabReportOCR.parseLabReport(text: text)
    #expect(output.reportDate == "2026-03-15", "Should parse 'Mar 15, 2026' format, got \(output.reportDate ?? "nil")")
}

@Test func dateParsingFullMonthName() {
    let text = "Collected: January 5, 2026\nGLUCOSE 89 mg/dL"
    let output = LabReportOCR.parseLabReport(text: text)
    #expect(output.reportDate == "2026-01-05", "Should parse 'January 5, 2026' format, got \(output.reportDate ?? "nil")")
}

@Test func dateParsingDDMonYYYY() {
    let text = "Collected: 15 Mar 2026\nGLUCOSE 89 mg/dL"
    let output = LabReportOCR.parseLabReport(text: text)
    #expect(output.reportDate == "2026-03-15", "Should parse '15 Mar 2026' format, got \(output.reportDate ?? "nil")")
}

// MARK: - Helper

private func findResult(_ biomarkerId: String, in text: String) -> LabReportOCR.ExtractedResult? {
    let output = LabReportOCR.parseLabReport(text: text)
    return output.results.first { $0.biomarkerId == biomarkerId }
}
