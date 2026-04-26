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
    ]

    /// Normalize a value from source unit to the standard unit for a biomarker.
    public static func normalize(biomarkerId: String, value: Double, fromUnit: String) -> (value: Double, unit: String) {
        guard let def = byId[biomarkerId] else { return (value, fromUnit) }

        // Already in standard unit
        let standardUnit = def.unit
        let cleanFrom = fromUnit.trimmingCharacters(in: .whitespaces)
        if cleanFrom == standardUnit || cleanFrom.lowercased() == standardUnit.lowercased() {
            return (value, standardUnit)
        }

        // Check conversion table
        if let conversions = unitConversions[biomarkerId],
           let multiplier = conversions[cleanFrom] {
            return (value * multiplier, standardUnit)
        }

        // No conversion found — return as-is
        return (value, cleanFrom)
    }
}
