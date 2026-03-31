import Foundation
import GRDB

struct FoodEntry: Identifiable, Codable, Sendable {
    var id: Int64?
    var mealLogId: Int64
    var foodId: Int64?        // nil if quick-add
    var foodName: String
    var servingSizeG: Double
    var servings: Double
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, servings, calories
        case mealLogId = "meal_log_id"
        case foodId = "food_id"
        case foodName = "food_name"
        case servingSizeG = "serving_size_g"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case createdAt = "created_at"
    }

    init(
        id: Int64? = nil,
        mealLogId: Int64,
        foodId: Int64? = nil,
        foodName: String,
        servingSizeG: Double,
        servings: Double = 1.0,
        calories: Double,
        proteinG: Double = 0,
        carbsG: Double = 0,
        fatG: Double = 0,
        fiberG: Double = 0,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.mealLogId = mealLogId
        self.foodId = foodId
        self.foodName = foodName
        self.servingSizeG = servingSizeG
        self.servings = servings
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.createdAt = createdAt
    }

    /// Total calories for this entry (per-serving * servings).
    var totalCalories: Double { calories * servings }
    var totalProtein: Double { proteinG * servings }
    var totalCarbs: Double { carbsG * servings }
    var totalFat: Double { fatG * servings }
    var totalFiber: Double { fiberG * servings }
}

extension FoodEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "food_entry"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension FoodEntry {
    /// Human-readable portion text: "2 eggs", "200g", etc.
    var portionText: String {
        guard servingSizeG > 0 else { return "" }
        let totalG = servingSizeG * servings
        let lower = foodName.lowercased()

        func fmt(_ n: Double, _ s: String, _ p: String) -> String {
            if n == 1 { return "1 \(s)" }
            if n == Double(Int(n)) { return "\(Int(n)) \(p)" }
            return String(format: "%.1f \(p)", n)
        }

        // Countable items (only when serving size matches a single piece)
        if lower.contains("egg") && servingSizeG < 80 { return fmt(servings, "egg", "eggs") }
        if lower.contains("meatball") && servingSizeG < 50 { return fmt(servings, "meatball", "meatballs") }
        if lower.contains("roti") || lower.contains("chapati") { return fmt(servings, "roti", "rotis") }
        if lower.contains("paratha") { return fmt(servings, "paratha", "parathas") }
        if lower.contains("naan") { return fmt(servings, "naan", "naans") }
        if lower.contains("dosa") { return fmt(servings, "dosa", "dosas") }
        if lower.contains("idli") { return fmt(servings, "idli", "idlis") }
        if lower.contains("samosa") { return fmt(servings, "samosa", "samosas") }
        if lower.contains("banana") && servingSizeG < 160 { return fmt(servings, "banana", "bananas") }
        if lower.contains("apple") && servingSizeG < 250 { return fmt(servings, "apple", "apples") }
        if lower.contains("cookie") || lower.contains("biscuit") { return fmt(servings, "piece", "pieces") }
        if lower.contains("slice") { return fmt(servings, "slice", "slices") }
        if lower.contains("scoop") { return fmt(servings, "scoop", "scoops") }
        if lower.contains("patty") || lower.contains("pattie") { return fmt(servings, "patty", "patties") }

        return "\(Int(totalG))g"
    }
}
