import Foundation

/// A single component of a multi-item recipe / combo / meal. Persisted as
/// JSON inside `food.ingredients` for combos saved via QuickAddView and
/// inferred-from-history combos auto-built by `AppDatabase`.
public struct RecipeItem: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var portionText: String
    public var calories: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var fiberG: Double
    public var servingSizeG: Double = 0

    public init(
        id: UUID = UUID(),
        name: String,
        portionText: String,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double,
        servingSizeG: Double = 0
    ) {
        self.id = id
        self.name = name
        self.portionText = portionText
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.servingSizeG = servingSizeG
    }
}
