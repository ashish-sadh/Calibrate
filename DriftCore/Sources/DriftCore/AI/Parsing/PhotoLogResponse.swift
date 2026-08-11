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

public extension PhotoLogItem {
    /// The one-line macro summary under an item's name on every AI review row
    /// (Describe, Snap, and — since #1135 — every Coach food-logging turn).
    ///
    /// `.rounded()` before `safeInt`, never a bare `Int()`. #1218: truncation
    /// turned Egg ×2's 0.8g of carbs into "C 0" and shaved a gram off protein
    /// and fat, so the last screen before committing a diary row disagreed
    /// with the iPhone card for the identical food. `safeInt` alone still
    /// truncates — it only clamps NaN/±∞/overflow — so both halves are load
    /// bearing. Same idiom as iOS's own review row and `FoodCardData`.
    ///
    /// Prebuilt as a String deliberately: `Text(stringVariable)` takes the
    /// verbatim overload, so a >999-cal item reads "1200 cal" on BOTH
    /// platforms rather than iOS-only "1,200".
    var reviewSummary: String {
        "\(calories.rounded().safeInt) cal · \(grams.rounded().safeInt)g"
            + " · P \(proteinG.rounded().safeInt)"
            + " C \(carbsG.rounded().safeInt)"
            + " F \(fatG.rounded().safeInt)"
    }

    /// Compact per-item line for AI-surface telemetry. Rounds like
    /// `reviewSummary` so a recorded turn agrees with what the user actually
    /// saw, which is the point of having it when debugging fallback rates.
    var telemetrySummary: String {
        "\(name) · \(calories.rounded().safeInt)cal · \(grams.rounded().safeInt)g"
    }

    /// Adapt a resolved recipe/combo component into a review row. The AI chat's
    /// composed-meal paths ("dal and rice", "add it to my breakfast") carry
    /// `RecipeItem`s; the editable review sheet speaks `PhotoLogItem`, so this
    /// is the one seam between them. #1135
    ///
    /// `resolveRecipeItem` already scales a RecipeItem's macros to the stated
    /// portion — passing them through unchanged is deliberate, NOT an omission.
    init(from item: RecipeItem) {
        self.init(
            name: item.name,
            grams: item.servingSizeG,
            calories: item.calories,
            proteinG: item.proteinG,
            carbsG: item.carbsG,
            fatG: item.fatG,
            fiberG: item.fiberG,
            confidence: .medium)
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
