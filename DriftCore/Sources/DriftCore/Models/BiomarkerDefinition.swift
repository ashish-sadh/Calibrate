import Foundation

/// Static definition of a biomarker from the knowledge base.
public struct BiomarkerDefinition: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let category: String
    public let unit: String
    public let optimalLow: Double
    public let optimalHigh: Double
    public let sufficientLow: Double
    public let sufficientHigh: Double
    public let absoluteLow: Double
    public let absoluteHigh: Double
    public let description: String
    public let whyItMatters: String
    public let relationships: String
    public let howToImprove: String
    public let healthMetrics: String
    public let impactCategories: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, category, unit, description, relationships
        case optimalLow = "optimal_low"
        case optimalHigh = "optimal_high"
        case sufficientLow = "sufficient_low"
        case sufficientHigh = "sufficient_high"
        case absoluteLow = "absolute_low"
        case absoluteHigh = "absolute_high"
        case whyItMatters = "why_it_matters"
        case howToImprove = "how_to_improve"
        case healthMetrics = "health_metrics"
        case impactCategories = "impact_categories"
    }

    /// Determine status for a given value.
    public func status(for value: Double) -> BiomarkerStatus {
        if value >= optimalLow && value <= optimalHigh {
            return .optimal
        } else if value >= sufficientLow && value <= sufficientHigh {
            return .sufficient
        } else {
            return .outOfRange
        }
    }

    /// Normalized position (0...1) of a value within the absolute range, clamped.
    public func normalizedPosition(for value: Double) -> Double {
        guard absoluteHigh > absoluteLow else { return 0.5 }
        return min(1, max(0, (value - absoluteLow) / (absoluteHigh - absoluteLow)))
    }
}

/// Status classification for a biomarker reading.
public enum BiomarkerStatus: String, Codable, Sendable, CaseIterable {
    case optimal
    case sufficient
    case outOfRange

    public var label: String {
        switch self {
        case .optimal: "Optimal"
        case .sufficient: "Sufficient"
        case .outOfRange: "Out of Range"
        }
    }

    public var iconName: String {
        switch self {
        case .optimal: "checkmark.circle.fill"
        case .sufficient: "circle.fill"
        case .outOfRange: "exclamationmark.triangle.fill"
        }
    }
}
