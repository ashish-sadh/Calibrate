import Foundation

/// Structured output returned from a cloud vision call. Mirrors the tool-use /
/// `response_format` schema we ask the model to produce, so parsing is a
/// plain `Codable` decode. #224 / #264.
///
/// We accept either string (`"high"`) or lowercased enum values from the
/// model. Items whose numeric macros are missing default to 0 and the item
/// is flagged low confidence downstream.
///
/// In DriftCore (moved from Drift/Services/CloudVision, #1101): the text
/// meal-parse path (`NebiusMealLogger`) shares this shape with the photo
/// path, and Android's Describe flow decodes it too.
public struct PhotoLogResponse: Codable, Equatable, Sendable {
    public var items: [PhotoLogItem]
    public var overallConfidence: Confidence
    public var notes: String?

    enum CodingKeys: String, CodingKey {
        case items
        case overallConfidence = "overall_confidence"
        case notes
    }

    public init(items: [PhotoLogItem], overallConfidence: Confidence, notes: String? = nil) {
        self.items = items
        self.overallConfidence = overallConfidence
        self.notes = notes
    }
}

public struct PhotoLogItem: Codable, Equatable, Sendable {
    public var name: String
    public var grams: Double
    public var calories: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    /// Dietary fiber in grams. Optional — older LLM responses don't have it.
    /// Decoder defaults to 0 when missing so macro rescale math stays valid.
    public var fiberG: Double
    public var confidence: Confidence
    /// LLM-suggested serving unit (g/oz/cup/tbsp/piece/slice). Optional —
    /// older responses and fallback paths won't have it. When present, we use
    /// it as the review-row default instead of the keyword heuristic.
    public var servingUnit: String?
    /// LLM-suggested amount in `servingUnit`. Optional — paired with
    /// `servingUnit`; either both present or both absent.
    public var servingAmount: Double?
    /// LLM-identified ingredient list for plant-points counting. Each entry
    /// is a lowercase plant name (e.g. ["tomato", "basil", "garlic"]).
    /// Optional — older responses won't have it; we fall back to the
    /// item's name for plant-points classification.
    public var ingredients: [String]?

    enum CodingKeys: String, CodingKey {
        case name, grams, calories, confidence, ingredients
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case servingUnit = "serving_unit"
        case servingAmount = "serving_amount"
    }

    public init(
        name: String,
        grams: Double,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double = 0,
        confidence: Confidence,
        servingUnit: String? = nil,
        servingAmount: Double? = nil,
        ingredients: [String]? = nil
    ) {
        self.name = name
        self.grams = grams
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.confidence = confidence
        self.servingUnit = servingUnit
        self.servingAmount = servingAmount
        self.ingredients = ingredients
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        grams = try c.decodeIfPresent(Double.self, forKey: .grams) ?? 0
        calories = try c.decodeIfPresent(Double.self, forKey: .calories) ?? 0
        proteinG = try c.decodeIfPresent(Double.self, forKey: .proteinG) ?? 0
        carbsG = try c.decodeIfPresent(Double.self, forKey: .carbsG) ?? 0
        fatG = try c.decodeIfPresent(Double.self, forKey: .fatG) ?? 0
        fiberG = try c.decodeIfPresent(Double.self, forKey: .fiberG) ?? 0
        confidence = try c.decodeIfPresent(Confidence.self, forKey: .confidence) ?? .low
        servingUnit = try c.decodeIfPresent(String.self, forKey: .servingUnit)
        servingAmount = try c.decodeIfPresent(Double.self, forKey: .servingAmount)
        ingredients = try c.decodeIfPresent([String].self, forKey: .ingredients)
    }
}

public enum Confidence: String, Codable, Equatable, CaseIterable, Sendable {
    case low, medium, high

    /// Lenient decoding: model sometimes returns "Medium" or "HIGH".
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self).lowercased()
        self = Confidence(rawValue: raw) ?? .low
    }
}
