import Foundation

/// Aggregated nutrition totals for a single day.
struct DailyNutrition: Sendable {
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double

    static let zero = DailyNutrition(calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0)

    var macroSummary: String {
        "\(Int(calories))cal \(Int(proteinG))P \(Int(carbsG))C \(Int(fatG))F"
    }
}
