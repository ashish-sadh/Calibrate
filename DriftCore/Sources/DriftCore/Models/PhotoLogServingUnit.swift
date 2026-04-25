import Foundation

/// Serving units shown in the Photo Log review picker. Intentionally separate
/// from the codebase-wide `ServingUnit` because that one requires a
/// `RawIngredient` for conversion and Photo Log items are free-form text the
/// LLM returns.
///
/// Conversion philosophy: grams is the canonical field (macros scale against
/// grams). `gramsPerUnit` is a display-time multiplier. For piece/slice we
/// use the LLM's original gram count as the "1-unit" baseline — "1 apple" from
/// the LLM's 182 g answer means 1 piece = 182 g — so switching to pieces and
/// editing the amount still produces sensible macros.
public enum PhotoLogServingUnit: String, CaseIterable, Codable, Sendable {
    case grams, ounces, cups, tablespoons, pieces, slices

    public var label: String {
        switch self {
        case .grams: return "g"
        case .ounces: return "oz"
        case .cups: return "cup"
        case .tablespoons: return "tbsp"
        case .pieces: return "piece"
        case .slices: return "slice"
        }
    }

    /// Grams per 1 unit for fixed-weight conversions. `piece`/`slice` return
    /// 0 here — callers must substitute the LLM's original grams as the
    /// 1-unit weight (see `PhotoLogEditableItem.gramsPerServingUnit`).
    public var fixedGramsPerUnit: Double? {
        switch self {
        case .grams: return 1
        case .ounces: return 28.3495
        case .cups: return 240        // water / liquid baseline, close enough for mixed plates
        case .tablespoons: return 15
        case .pieces, .slices: return nil
        }
    }

    /// Keyword fallback used only when the LLM didn't return a `serving_unit`
    /// (older responses, malformed payloads, or when the model declined).
    /// Primary source is the AI — food_log tool schema asks for it. This
    /// table stays short and covers the common English dish keywords.
    public static func suggested(forName name: String) -> PhotoLogServingUnit {
        let n = name.lowercased()
        if ["slice", "pizza", "toast", "bread", "cake", "pie"].contains(where: n.contains) {
            return .slices
        }
        if ["apple", "banana", "orange", "egg", "cookie", "bar", "muffin", "samosa", "dosa", "idli", "burger", "taco", "dumpling"]
            .contains(where: n.contains) {
            return .pieces
        }
        if ["rice", "soup", "curry", "salad", "oats", "yogurt", "cereal", "dal", "smoothie", "stew"]
            .contains(where: n.contains) {
            return .cups
        }
        if ["oil", "butter", "ghee", "honey", "syrup", "peanut butter", "dressing"]
            .contains(where: n.contains) {
            return .tablespoons
        }
        return .grams
    }

    /// Parse an LLM-returned serving unit string, tolerating common variants
    /// ("piece" vs "pieces", "gram"/"g", "ml" as volume fallback). Returns
    /// nil when the string doesn't map to a supported unit so callers can
    /// fall back to the keyword heuristic.
    public static func parse(_ raw: String?) -> PhotoLogServingUnit? {
        guard let raw, !raw.isEmpty else { return nil }
        let normalized = raw.lowercased().trimmingCharacters(in: .whitespaces)
        switch normalized {
        case "grams", "gram", "g":                             return .grams
        case "ounces", "ounce", "oz":                          return .ounces
        case "cups", "cup", "c":                               return .cups
        case "tablespoons", "tablespoon", "tbsp", "tbs", "tb": return .tablespoons
        case "pieces", "piece", "pc", "unit", "units", "each": return .pieces
        case "slices", "slice":                                return .slices
        default:                                               return nil
        }
    }
}
