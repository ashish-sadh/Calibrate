import Foundation

/// Provides access to the bundled biomarker definitions.
public enum BiomarkerKnowledgeBase {

    /// All 65 biomarker definitions, loaded from biomarkers.json.
    public static let all: [BiomarkerDefinition] = {
        guard let url = Bundle.module.url(forResource: "biomarkers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let defs = try? JSONDecoder().decode([BiomarkerDefinition].self, from: data) else {
            Log.biomarkers.error("Failed to load biomarkers.json")
            return []
        }
        return defs
    }()

    /// Lookup by ID.
    public static let byId: [String: BiomarkerDefinition] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()

    /// All unique categories in display order.
    public static let categories: [String] = {
        var seen = Set<String>()
        var result: [String] = []
        let order = ["Heart Health", "Metabolic Health", "Hormones", "Thyroid",
                     "Vitamins & Minerals", "Inflammation", "Blood Cells",
                     "Liver", "Kidney"]
        for cat in order {
            if all.contains(where: { $0.category == cat }) {
                seen.insert(cat)
                result.append(cat)
            }
        }
        // Append any categories not in the predefined order
        for def in all where !seen.contains(def.category) {
            seen.insert(def.category)
            result.append(def.category)
        }
        return result
    }()

    /// Biomarkers grouped by category.
    public static let byCategory: [String: [BiomarkerDefinition]] = {
        Dictionary(grouping: all, by: \.category)
    }()

    /// All unique impact categories across all biomarkers.
    public static let impactCategories: [String] = {
        var seen = Set<String>()
        var result: [String] = []
        for def in all {
            for cat in def.impactCategories where !seen.contains(cat) {
                seen.insert(cat)
                result.append(cat)
            }
        }
        return result
    }()

    /// Unit conversion table for normalizing different lab formats.
    /// Key: (biomarker_id, source_unit) -> multiplier to convert to standard unit.
    public static let unitConversions: [String: [String: Double]] = [
        // Cholesterol: mmol/L -> mg/dL (multiply by 38.67)
        "total_cholesterol": ["mmol/L": 38.67, "mmol/l": 38.67],
        "hdl_cholesterol": ["mmol/L": 38.67, "mmol/l": 38.67],
        "ldl_cholesterol": ["mmol/L": 38.67, "mmol/l": 38.67],
        "non_hdl_cholesterol": ["mmol/L": 38.67, "mmol/l": 38.67],
        // Triglycerides: mmol/L -> mg/dL (multiply by 88.57)
        "triglycerides": ["mmol/L": 88.57, "mmol/l": 88.57],
        // Glucose: mmol/L -> mg/dL (multiply by 18.018)
        "glucose": ["mmol/L": 18.018, "mmol/l": 18.018],
        // Vitamin D: nmol/L -> ng/mL (divide by 2.496)
        "vitamin_d": ["nmol/L": 1.0 / 2.496, "nmol/l": 1.0 / 2.496],
        // B12: pmol/L -> pg/mL (divide by 0.7378)
        "vitamin_b12": ["pmol/L": 1.0 / 0.7378, "pmol/l": 1.0 / 0.7378],
        // Testosterone: nmol/L -> ng/dL (multiply by 28.842)
        "testosterone_total": ["nmol/L": 28.842, "nmol/l": 28.842],
        // Iron: umol/L -> ug/dL (multiply by 5.587)
        "iron": ["umol/L": 5.587, "umol/l": 5.587],
        // Ferritin: ug/L -> ng/mL (1:1)
        "ferritin": ["ug/L": 1.0, "ug/l": 1.0, "mcg/L": 1.0],
        // Creatinine: umol/L -> mg/dL (divide by 88.42)
        "creatinine": ["umol/L": 1.0 / 88.42, "umol/l": 1.0 / 88.42],
        // BUN: mmol/L -> mg/dL (multiply by 2.801)
        "bun": ["mmol/L": 2.801, "mmol/l": 2.801],
        // Calcium: mmol/L -> mg/dL (multiply by 4.008)
        "calcium": ["mmol/L": 4.008, "mmol/l": 4.008],
        // Cortisol: nmol/L -> ug/dL (divide by 27.59)
        "cortisol": ["nmol/L": 1.0 / 27.59, "nmol/l": 1.0 / 27.59],
        // WBC / platelets reported as absolute cells -> K/uL (2026-07-14: Indian
        // reports use cells/uL and /cumm; without this the value stayed 7200 vs
        // a 1–30 K/uL range and showed a false out-of-range status).
        "wbc": ["cells/uL": 0.001, "cells/ul": 0.001, "/cumm": 0.001, "cells/cumm": 0.001, "cumm": 0.001],
        "platelets": ["cells/uL": 0.001, "cells/ul": 0.001, "/cumm": 0.001, "cells/cumm": 0.001, "cumm": 0.001, "lakh/cumm": 100.0],
        // Thyroid free hormones — pmol/L is the international default (~13× off
        // if stored raw).
        "free_t4": ["pmol/L": 0.0777, "pmol/l": 0.0777],
        "free_t3": ["pmol/L": 0.651, "pmol/l": 0.651],
        "estradiol": ["pmol/L": 1.0 / 3.671, "pmol/l": 1.0 / 3.671],
        // Common international SI units with no prior conversion.
        "uric_acid": ["umol/L": 1.0 / 59.48, "umol/l": 1.0 / 59.48],
        "magnesium": ["mmol/L": 2.43, "mmol/l": 2.43],
        "phosphorus": ["mmol/L": 3.097, "mmol/l": 3.097],
        "urea": ["mmol/L": 6.006, "mmol/l": 6.006],   // urea mmol/L -> mg/dL
    ]

    /// Conversion multiplier to the standard unit for a marker, or nil when
    /// none applies (already-standard or unknown). Shared by value AND
    /// reference-bound conversion so they never end up on different scales.
    public static func conversionMultiplier(biomarkerId: String, fromUnit: String) -> Double? {
        guard let def = byId[biomarkerId] else { return nil }
        let cleanFrom = fromUnit.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\u{00B5}", with: "u")
            .replacingOccurrences(of: "\u{03BC}", with: "u")
        if cleanFrom == def.unit || cleanFrom.lowercased() == def.unit.lowercased() { return 1.0 }
        return unitConversions[biomarkerId]?[cleanFrom]
    }

    /// Normalize a value from source unit to the standard unit for a biomarker.
    public static func normalize(biomarkerId: String, value: Double, fromUnit: String) -> (value: Double, unit: String) {
        guard let def = byId[biomarkerId] else { return (value, fromUnit) }
        let cleanFrom = fromUnit.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\u{00B5}", with: "u")
            .replacingOccurrences(of: "\u{03BC}", with: "u")
        if let multiplier = conversionMultiplier(biomarkerId: biomarkerId, fromUnit: cleanFrom) {
            return (value * multiplier, def.unit)
        }
        // No conversion found — return as-is (with the micro-sign cleaned).
        return (value, cleanFrom)
    }

    /// Convert a value AND its reference bounds together so they never end up on
    /// different scales (2026-07-14 fix: value was converted while the stored
    /// reference bounds stayed in the source unit).
    public static func normalizeResult(
        biomarkerId: String, value: Double, fromUnit: String,
        referenceLow: Double?, referenceHigh: Double?
    ) -> (value: Double, unit: String, referenceLow: Double?, referenceHigh: Double?) {
        let (v, u) = normalize(biomarkerId: biomarkerId, value: value, fromUnit: fromUnit)
        guard let m = conversionMultiplier(biomarkerId: biomarkerId, fromUnit: fromUnit), m != 1.0 else {
            return (v, u, referenceLow, referenceHigh)
        }
        return (v, u, referenceLow.map { $0 * m }, referenceHigh.map { $0 * m })
    }
}
