import Foundation

/// Explicit biomarker aliases for the deterministic lab parser. No fallback to
/// `definition.name` — that would let percentage WBC-differential lines match
/// their absolute-count twins and vice-versa. Ordering within a marker matters
/// where one alias is a prefix of another (e.g. testosterone total before free).
///
/// Indian-lab conventions are first-class here (SGPT/SGOT, "urea" for BUN,
/// bare A/G, ESR) — Indian reports are the primary user base.
public enum LabAliases {

    public static let byBiomarkerId: [String: [String]] = [
        "total_cholesterol": ["cholesterol, total", "cholesterol,total", "total cholesterol", "cholesterol - total", "serum cholesterol", "t. cholesterol", "t.cholesterol", "s. cholesterol", "s.cholesterol"],
        "hdl_cholesterol": ["hdl cholesterol", "hdl-c", "hdl chol", "hdl - cholesterol", "cholesterol - hdl", "hdl"],
        "ldl_cholesterol": ["ldl cholesterol", "ldl-cholesterol", "ldl-c", "ldl chol calc", "ldl chol", "ldl - cholesterol", "cholesterol - ldl", "ldl"],
        "vldl_cholesterol": ["vldl cholesterol", "vldl-c", "vldl chol", "vldl"],
        "triglycerides": ["triglycerides", "triglyceride", "serum triglycerides", "tg"],
        "non_hdl_cholesterol": ["non hdl cholesterol", "non-hdl cholesterol", "non hdl", "non-hdl"],
        "apolipoprotein_b": ["apolipoprotein b", "apo b", "apob"],
        "lipoprotein_a": ["lipoprotein (a)", "lipoprotein(a)", "lp(a)"],
        "glucose": ["glucose, fasting", "fasting glucose", "glucose fasting", "fasting blood sugar",
                    "post prandial blood sugar", "random blood sugar", "blood glucose",
                    "blood sugar", "rbs", "fbs", "ppbs", "glucose"],
        "hba1c": ["hemoglobin a1c", "hba1c", "glycated hemoglobin", "glycosylated hemoglobin", "hb a1c", "a1c"],
        "insulin": ["insulin, fasting", "fasting insulin", "insulin"],
        "homa_ir": ["homa-ir", "homa ir", "homa index"],
        "testosterone_total": ["testosterone, total", "testosterone,total", "total testosterone"],
        "free_testosterone": ["testosterone, free", "testosterone,free", "free testosterone"],
        "estradiol": ["estradiol", "e2"],
        "progesterone": ["progesterone"],
        "prolactin": ["prolactin", "prl"],
        "shbg": ["sex hormone binding globulin", "shbg"],
        "cortisol": ["cortisol, total", "cortisol,total", "cortisol - morning", "cortisol"],
        "dhea_s": ["dhea sulfate", "dhea-s", "dhea-sulfate", "dheas"],
        "fsh": ["follicle stimulating hormone", "fsh"],
        "lh": ["luteinizing hormone", "lh"],
        "thyroid_tsh": ["thyroid stimulating hormone", "tsh - ultrasensitive", "tsh, ultrasensitive", "tsh"],
        "free_t4": ["free t4", "ft4", "t4, free", "free thyroxine"],
        "free_t3": ["free t3", "ft3", "t3, free", "free triiodothyronine"],
        "total_t4": ["total t4", "t4, total", "thyroxine (t4)", "thyroxine total", "t4 total"],
        "total_t3": ["total t3", "t3, total", "triiodothyronine (t3)", "triiodothyronine total", "t3 total"],
        "vitamin_d": ["vitamin d,25-oh", "vitamin d, 25-oh", "vitamin d 25-oh", "25-hydroxyvitamin d", "25 oh vitamin d", "25(oh)d", "vitamin d (25-oh)", "vitamin d3", "vitamin d", "vit d3", "vit. d3", "vit d", "vit. d", "vit-d"],
        "vitamin_b12": ["vitamin b12", "vitamin b-12", "b-12", "b12", "cobalamin", "cyanocobalamin"],
        "folate": ["folate", "folic acid", "serum folate"],
        "iron": ["iron, total", "iron,total", "serum iron", "iron"],
        "ferritin": ["ferritin", "serum ferritin"],
        "iron_saturation": ["% saturation", "iron saturation", "iron % saturation", "transferrin sat", "transferrin saturation"],
        "calcium": ["calcium, total", "calcium,total", "serum calcium", "calcium"],
        "magnesium": ["magnesium", "serum magnesium"],
        "zinc": ["zinc"],
        "hs_crp": ["hs crp", "hs-crp", "high sensitivity c-reactive protein", "hs c-reactive protein", "c-reactive protein"],
        "esr": ["erythrocyte sedimentation rate", "esr", "sed rate"],
        "homocysteine": ["homocysteine"],
        "hemoglobin": ["hemoglobin", "haemoglobin", "hgb", "hb"],
        "hematocrit": ["hematocrit", "haematocrit", "hct", "pcv", "packed cell volume"],
        "rbc": ["rbc count", "rbc", "red blood cell count", "red blood cell", "total rbc"],
        "mcv": ["mcv", "mean corpuscular volume"],
        "mch": ["mch", "mean corpuscular hemoglobin"],
        "mchc": ["mchc"],
        "rdw": ["rdw-cv", "rdw cv", "rdw"],
        "platelets": ["platelet count", "platelets", "plt"],
        "wbc": ["wbc count", "total leukocyte count", "total wbc count", "wbc", "white blood cell count", "white blood cell", "tlc"],

        // WBC differentials — absolute counts (require "absolute" marker)
        "neutrophils": ["absolute neutrophils", "neutrophils (absolute)", "neut abs", "absolute neutrophil count"],
        "lymphocytes": ["absolute lymphocytes", "lymphocytes (absolute)", "lymphs (absolute)", "lymph abs", "absolute lymphocyte count"],
        "monocytes": ["absolute monocytes", "monocytes (absolute)", "monocytes(absolute)", "monocytes(absol", "mono abs"],
        "eosinophils": ["absolute eosinophils", "eosinophils (absolute)", "eos (absolute)", "eos abs"],
        "basophils": ["absolute basophils", "basophils (absolute)", "baso (absolute)", "baso abs"],

        // WBC differentials — percentage
        "neutrophil_pct": ["neutrophils", "neutrophil %", "neut %"],
        "lymphocyte_pct": ["lymphocytes", "lymphs", "lymphocyte %", "lymph %"],
        "monocyte_pct": ["monocytes", "monocyte %", "mono %"],
        "eosinophil_pct": ["eosinophils", "eosinophil %", "eos %", "eos"],
        "basophil_pct": ["basophils", "basophil %", "baso %", "basos"],

        // Liver — SGPT/SGOT are the Indian-standard names for ALT/AST
        "alt": ["alt (sgpt)", "alt(sgpt)", "sgpt", "alanine aminotransferase", "alanine transaminase", "alt"],
        "ast": ["ast (sgot)", "ast(sgot)", "sgot", "aspartate aminotransferase", "aspartate transaminase", "ast"],
        "alp": ["alkaline phosphatase", "alkaline", "alk phos", "alp"],
        "albumin": ["albumin", "serum albumin"],
        "globulin": ["globulin, total", "globulin,total", "serum globulin", "globulin"],
        "ag_ratio": ["a/g ratio", "albumin/globulin ratio", "albumin / globulin ratio", "albumin globulin ratio", "albumin/globulin"],
        "total_protein": ["protein, total", "protein,total", "total protein", "serum total protein"],
        "total_bilirubin": ["bilirubin, total", "bilirubin,total", "total bilirubin", "bilirubin - total", "serum bilirubin total"],
        "direct_bilirubin": ["bilirubin, direct", "bilirubin,direct", "direct bilirubin", "bilirubin - direct", "conjugated bilirubin"],
        "ggt": ["gamma-glutamyl transferase", "gamma glutamyl transferase", "ggt", "gamma-glutamyl", "gamma glutamyl", "ggtp"],

        // Kidney
        "bun": ["urea nitrogen (bun)", "urea nitrogen", "blood urea nitrogen", "bun"],
        "urea": ["blood urea", "urea", "serum urea"],
        "creatinine": ["creatinine, serum", "serum creatinine", "creatinine"],
        "egfr": ["egfr if nonafricn", "estimated gfr", "egfr", "gfr estimated"],
        "uric_acid": ["uric acid, serum", "serum uric acid", "uric acid"],
        "sodium": ["sodium", "serum sodium", "na+"],
        "potassium": ["potassium", "serum potassium", "k+"],
        "chloride": ["chloride", "serum chloride"],
        "co2": ["carbon dioxide, total", "carbon dioxide,total", "carbon dioxide", "bicarbonate", "co2"],
        "phosphorus": ["phosphorus", "phosphate", "inorganic phosphorus"],
        "tibc": ["total iron binding capacity", "iron binding capacity", "iron binding", "tibc"],

        // Prostate / other common panels
        "psa": ["prostate specific antigen", "psa, total", "total psa", "psa"],
    ]

    /// IDs that represent percentage WBC differentials.
    public static let pctBiomarkerIds: Set<String> = [
        "neutrophil_pct", "lymphocyte_pct", "monocyte_pct", "eosinophil_pct", "basophil_pct"
    ]

    /// IDs that represent absolute WBC differentials.
    public static let absBiomarkerIds: Set<String> = [
        "neutrophils", "lymphocytes", "monocytes", "eosinophils", "basophils"
    ]
}

/// Maps the lowerCamelCase IDs the Apple Foundation Models extractor is prompted
/// to emit (`ldl`, `vitaminD`, `tsh`) onto the canonical snake_case catalog IDs
/// (`ldl_cholesterol`, `vitamin_d`, `thyroid_tsh`). Before this map existed
/// (2026-07-14) FM results bypassed catalog validation, saved as un-nameable
/// rows the UI couldn't range-check, and duplicated regex rows because the two
/// ID schemes never collided during dedup.
public enum BiomarkerCatalogMap {

    /// Explicit camelCase → snake_case overrides where a naive de-camel doesn't
    /// land on the catalog ID (mostly the "…_cholesterol"/"thyroid_…" suffixes).
    private static let overrides: [String: String] = [
        "ldl": "ldl_cholesterol",
        "hdl": "hdl_cholesterol",
        "vldl": "vldl_cholesterol",
        "totalcholesterol": "total_cholesterol",
        "nonhdlcholesterol": "non_hdl_cholesterol",
        "nonhdl": "non_hdl_cholesterol",
        "tsh": "thyroid_tsh",
        "vitamind": "vitamin_d",
        "vitamind3": "vitamin_d",
        "vitaminb12": "vitamin_b12",
        "b12": "vitamin_b12",
        "hemoglobina1c": "hba1c",
        "a1c": "hba1c",
        "sgpt": "alt",
        "sgot": "ast",
        "totaltestosterone": "testosterone_total",
        "freetestosterone": "free_testosterone",
        "totalprotein": "total_protein",
        "totalbilirubin": "total_bilirubin",
        "directbilirubin": "direct_bilirubin",
        "uricacid": "uric_acid",
        "crp": "hs_crp",
        "hscrp": "hs_crp",
        "apob": "apolipoprotein_b",
        "lpa": "lipoprotein_a",
        "totalt3": "total_t3",
        "totalt4": "total_t4",
        "freet3": "free_t3",
        "freet4": "free_t4",
        "agratio": "ag_ratio",
    ]

    /// Resolve any extractor-emitted ID to a canonical catalog ID, or nil if it
    /// isn't a known biomarker. Accepts already-canonical snake_case unchanged.
    public static func canonicalID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Already canonical?
        if BiomarkerKnowledgeBase.byId[trimmed] != nil { return trimmed }
        let lowered = trimmed.lowercased()
        if BiomarkerKnowledgeBase.byId[lowered] != nil { return lowered }
        // Strip separators to a bare token, then override or de-camel.
        let bare = lowered.replacingOccurrences(of: "[ _-]", with: "", options: .regularExpression)
        if let mapped = overrides[bare] { return mapped }
        // snake_case candidate: insert underscores at camel humps of the raw.
        let snaked = camelToSnake(trimmed)
        if BiomarkerKnowledgeBase.byId[snaked] != nil { return snaked }
        return nil
    }

    private static func camelToSnake(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch.isUppercase {
                if !out.isEmpty { out += "_" }
                out += ch.lowercased()
            } else {
                out.append(ch)
            }
        }
        return out
    }
}
