import Foundation

/// Aggregated nutrition totals for a single day.
public struct DailyNutrition: Sendable {
    public var calories: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var fiberG: Double

    public init(calories: Double, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
    }

    public static let zero = DailyNutrition(calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0)

    public var macroSummary: String {
        "\(Int(calories))cal \(Int(proteinG))P \(Int(carbsG))C \(Int(fatG))F"
    }
}
