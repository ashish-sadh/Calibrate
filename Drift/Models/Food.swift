import Foundation
import GRDB

struct Food: Identifiable, Codable, Sendable {
    var id: Int64?
    var name: String
    var category: String
    var servingSize: Double
    var servingUnit: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var ingredients: String?  // JSON array of ingredient names, e.g. '["rice","onion","turmeric"]'
    var source: String?       // "database", "recipe", "barcode", "custom". nil = database (legacy)
    var isRecipe: Bool = false
    var sortOrder: Int = 0
    var defaultServings: Double = 1
    var novaGroup: Int?       // NOVA 1-4: processing level for plant points
    /// When true (recipes only), logging this recipe inserts one FoodEntry
    /// per ingredient instead of a single aggregated entry — lets users
    /// treat a recipe as a named meal "group" (e.g. coffee + protein + creatine).
    var expandOnLog: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, category, calories, ingredients, source
        case isRecipe = "is_recipe"
        case sortOrder = "sort_order"
        case defaultServings = "default_servings"
        case novaGroup = "nova_group"
        case expandOnLog = "expand_on_log"
        case servingSize = "serving_size"
        case servingUnit = "serving_unit"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
    }

    init(
        id: Int64? = nil,
        name: String,
        category: String,
        servingSize: Double,
        servingUnit: String,
        calories: Double,
        proteinG: Double = 0,
        carbsG: Double = 0,
        fatG: Double = 0,
        fiberG: Double = 0,
        ingredients: String? = nil,
        source: String? = nil,
        isRecipe: Bool = false,
        sortOrder: Int = 0,
        defaultServings: Double = 1,
        novaGroup: Int? = nil,
        expandOnLog: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.servingSize = servingSize
        self.servingUnit = servingUnit
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.ingredients = ingredients
        self.source = source
        self.isRecipe = isRecipe
        self.sortOrder = sortOrder
        self.defaultServings = defaultServings
        self.novaGroup = novaGroup
        self.expandOnLog = expandOnLog
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(String.self, forKey: .category)
        servingSize = try c.decode(Double.self, forKey: .servingSize)
        servingUnit = try c.decode(String.self, forKey: .servingUnit)
        calories = try c.decode(Double.self, forKey: .calories)
        proteinG = try c.decodeIfPresent(Double.self, forKey: .proteinG) ?? 0
        carbsG = try c.decodeIfPresent(Double.self, forKey: .carbsG) ?? 0
        fatG = try c.decodeIfPresent(Double.self, forKey: .fatG) ?? 0
        fiberG = try c.decodeIfPresent(Double.self, forKey: .fiberG) ?? 0
        // ingredients: accept array from JSON file or string from DB
        if let arr = try? c.decode([String].self, forKey: .ingredients) {
            ingredients = (try? JSONEncoder().encode(arr)).flatMap { String(data: $0, encoding: .utf8) }
        } else {
            ingredients = try c.decodeIfPresent(String.self, forKey: .ingredients)
        }
        source = try c.decodeIfPresent(String.self, forKey: .source)
        isRecipe = try c.decodeIfPresent(Bool.self, forKey: .isRecipe) ?? false
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        defaultServings = try c.decodeIfPresent(Double.self, forKey: .defaultServings) ?? 1
        novaGroup = try c.decodeIfPresent(Int.self, forKey: .novaGroup)
        expandOnLog = try c.decodeIfPresent(Bool.self, forKey: .expandOnLog) ?? false
    }

    /// Compact macro string like "165cal 31P 0C 4F"
    var macroSummary: String {
        "\(Int(calories))cal \(Int(proteinG))P \(Int(carbsG))C \(Int(fatG))F"
    }

    /// Parsed ingredient names. Handles both legacy ["name"] and new [{...}] formats.
    var ingredientList: [String] {
        guard let json = ingredients, let data = json.data(using: .utf8) else { return [name] }
        // Try new format first (array of objects with "name" key)
        if let items = try? JSONDecoder().decode([QuickAddView.RecipeItem].self, from: data) {
            let names = items.map(\.name)
            return names.isEmpty ? [name] : names
        }
        // Legacy format (array of strings)
        if let arr = try? JSONDecoder().decode([String].self, from: data) {
            return arr.isEmpty ? [name] : arr
        }
        return [name]
    }

    /// Full recipe items with per-ingredient macros. Returns nil for non-recipe or legacy format.
    var recipeItems: [QuickAddView.RecipeItem]? {
        guard let json = ingredients, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([QuickAddView.RecipeItem].self, from: data)
    }
}

extension Food: FetchableRecord, PersistableRecord {
    static let databaseTableName = "food"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
