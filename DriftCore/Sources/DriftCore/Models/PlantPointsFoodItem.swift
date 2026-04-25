import Foundation

/// Cross-platform value type for an entry being classified into plant points.
/// The classifier (`PlantPointsService`) lives in iOS for now; the data shape
/// lives here so `AppDatabase.fetchFoodItemsForPlantPoints` can return a
/// platform-neutral type.
public struct PlantPointsFoodItem: Sendable {
    public let name: String
    public let ingredients: [String]?    // parsed ingredient names, nil = use name
    public let novaGroup: Int?            // 1-4, nil = treat as unprocessed

    public init(name: String, ingredients: [String]? = nil, novaGroup: Int? = nil) {
        self.name = name
        self.ingredients = ingredients
        self.novaGroup = novaGroup
    }
}
