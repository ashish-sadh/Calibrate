import Foundation
import GRDB

struct FavoriteFood: Identifiable, Codable, Sendable {
    var id: Int64?
    var name: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var defaultServings: Double
    var isRecipe: Bool
    var sortOrder: Int
    var createdAt: String
    var ingredients: String?  // JSON array of ingredient names

    enum CodingKeys: String, CodingKey {
        case id, name, calories, ingredients
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case defaultServings = "default_servings"
        case isRecipe = "is_recipe"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }

    init(id: Int64? = nil, name: String, calories: Double, proteinG: Double = 0, carbsG: Double = 0,
         fatG: Double = 0, fiberG: Double = 0, defaultServings: Double = 1, isRecipe: Bool = false,
         sortOrder: Int = 0, createdAt: String = ISO8601DateFormatter().string(from: Date()),
         ingredients: String? = nil) {
        self.id = id; self.name = name; self.calories = calories; self.proteinG = proteinG
        self.carbsG = carbsG; self.fatG = fatG; self.fiberG = fiberG
        self.defaultServings = defaultServings; self.isRecipe = isRecipe
        self.sortOrder = sortOrder; self.createdAt = createdAt; self.ingredients = ingredients
    }

    /// Parsed ingredient names. Falls back to [name].
    var ingredientList: [String] {
        guard let json = ingredients,
              let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return [name]
        }
        return arr.isEmpty ? [name] : arr
    }

    var macroSummary: String { "\(Int(calories))cal \(Int(proteinG))P \(Int(carbsG))C \(Int(fatG))F" }
}

extension FavoriteFood: FetchableRecord, PersistableRecord {
    static let databaseTableName = "favorite_food"
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
