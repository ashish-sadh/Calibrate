import Foundation

/// Structured output returned from a cloud vision call. Mirrors the tool-use /
/// `response_format` schema we ask the model to produce, so parsing is a
/// plain `Codable` decode. #224 / #264.
///
/// We accept either string (`"high"`) or lowercased enum values from the
/// model. Items whose numeric macros are missing default to 0 and the item
/// is flagged low confidence downstream.
struct PhotoLogResponse: Codable, Equatable {
    var items: [PhotoLogItem]
    var overallConfidence: Confidence
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case items
        case overallConfidence = "overall_confidence"
        case notes
    }
}

struct PhotoLogItem: Codable, Equatable {
    var name: String
    var grams: Double
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var confidence: Confidence

    enum CodingKeys: String, CodingKey {
        case name, grams, calories, confidence
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }

    init(
        name: String,
        grams: Double,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        confidence: Confidence
    ) {
        self.name = name
        self.grams = grams
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        grams = try c.decodeIfPresent(Double.self, forKey: .grams) ?? 0
        calories = try c.decodeIfPresent(Double.self, forKey: .calories) ?? 0
        proteinG = try c.decodeIfPresent(Double.self, forKey: .proteinG) ?? 0
        carbsG = try c.decodeIfPresent(Double.self, forKey: .carbsG) ?? 0
        fatG = try c.decodeIfPresent(Double.self, forKey: .fatG) ?? 0
        confidence = try c.decodeIfPresent(Confidence.self, forKey: .confidence) ?? .low
    }
}

enum Confidence: String, Codable, Equatable, CaseIterable {
    case low, medium, high

    /// Lenient decoding: model sometimes returns "Medium" or "HIGH".
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self).lowercased()
        self = Confidence(rawValue: raw) ?? .low
    }
}
