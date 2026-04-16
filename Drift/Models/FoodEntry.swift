import Foundation
import GRDB

struct FoodEntry: Identifiable, Codable, Sendable {
    var id: Int64?
    var mealLogId: Int64      // kept for backwards compat (legacy FK to meal_log)
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
    var loggedAt: String
    var date: String?         // "YYYY-MM-DD" — which day this belongs to
    var mealType: String?     // "breakfast" | "lunch" | "dinner" | "snack"

    enum CodingKeys: String, CodingKey {
        case id, servings, calories, date
        case mealLogId = "meal_log_id"
        case foodId = "food_id"
        case foodName = "food_name"
        case servingSizeG = "serving_size_g"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case createdAt = "created_at"
        case loggedAt = "logged_at"
        case mealType = "meal_type"
    }

    init(
        id: Int64? = nil,
        mealLogId: Int64 = 0,
        foodId: Int64? = nil,
        foodName: String,
        servingSizeG: Double,
        servings: Double = 1.0,
        calories: Double,
        proteinG: Double = 0,
        carbsG: Double = 0,
        fatG: Double = 0,
        fiberG: Double = 0,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        loggedAt: String = ISO8601DateFormatter().string(from: Date()),
        date: String? = nil,
        mealType: String? = nil
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
        self.loggedAt = loggedAt
        self.date = date
        self.mealType = mealType
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
        if lower.contains("brownie") || lower.contains("cupcake") { return fmt(servings, "piece", "pieces") }
        if lower.contains("momo") { return fmt(servings, "momo", "momos") }
        if lower.contains("vada") && servingSizeG < 120 { return fmt(servings, "vada", "vadas") }
        if lower.contains("pakora") { return fmt(servings, "pakora", "pakoras") }
        if lower.contains("uttapam") && servingSizeG < 150 { return fmt(servings, "uttapam", "uttapams") }
        if lower.contains("kachori") && servingSizeG < 200 { return fmt(servings, "kachori", "kachoris") }
        // Indian sweets
        if lower.contains("laddu") || lower.contains("laddoo") || lower.contains("barfi") ||
           lower.contains("burfi") || lower.contains("jalebi") || lower.contains("rasgulla") ||
           lower.contains("modak") || lower.contains("peda") || lower.contains("gujiya") ||
           lower.contains("kaju katli") { return fmt(servings, "piece", "pieces") }
        // Indian snack pieces
        if lower.contains("omelette") || lower.contains("omelet") || lower.contains("frittata") {
            return fmt(servings, "omelette", "omelettes")
        }
        if lower.contains("khakhra") { return fmt(servings, "khakhra", "khakhras") }
        if lower.contains("dhokla") || lower.contains("khaman") || lower.contains("fafda") ||
           lower.contains("handvo") || lower.contains("chilla") || lower.contains("cheela") {
            return fmt(servings, "piece", "pieces")
        }
        if lower.contains("pav bhaji") || lower.contains("misal") {
            return fmt(servings, "bowl", "bowls")
        }
        if lower.contains("nugget") { return fmt(servings, "nugget", "nuggets") }
        if lower.contains("wing") && servingSizeG < 100 { return fmt(servings, "wing", "wings") }
        if lower.contains("strip") && servingSizeG < 50 { return fmt(servings, "strip", "strips") }
        if lower.contains("link") && servingSizeG < 100 { return fmt(servings, "link", "links") }
        if lower.contains("slice") { return fmt(servings, "slice", "slices") }
        // Bread/toast → slice (exclude breadfruit, breadstick, per-slice entries already caught above)
        if (lower.contains("bread") || lower.contains("toast")) &&
           !lower.contains("breadfruit") && !lower.contains("breadstick") && servingSizeG < 80 {
            return fmt(servings, "slice", "slices")
        }
        // Pizza → slice
        if lower.contains("pizza") && servingSizeG < 150 { return fmt(servings, "slice", "slices") }
        if lower.contains("scoop") { return fmt(servings, "scoop", "scoops") }
        // Protein powder → scoop (food name doesn't contain "scoop")
        if lower.contains("protein powder") { return fmt(servings, "scoop", "scoops") }
        if lower.contains("patty") || lower.contains("pattie") { return fmt(servings, "patty", "patties") }
        if lower.contains("bar") && !lower.contains("barley") && servingSizeG < 80 { return fmt(servings, "bar", "bars") }
        if lower.contains("tortilla") && servingSizeG < 80 { return fmt(servings, "tortilla", "tortillas") }
        if lower.contains("pancake") && servingSizeG < 100 { return fmt(servings, "pancake", "pancakes") }
        if lower.contains("waffle") && servingSizeG < 100 { return fmt(servings, "waffle", "waffles") }
        if lower.contains("muffin") && servingSizeG < 120 { return fmt(servings, "muffin", "muffins") }
        if lower.contains("bagel") && servingSizeG < 130 { return fmt(servings, "bagel", "bagels") }
        if lower.contains("cup") && servingSizeG > 200 { return fmt(servings, "cup", "cups") }
        // Standalone pav (bread roll)
        let lowerWords = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        if lowerWords.contains("pav") { return fmt(servings, "pav", "pavs") }
        // Soups, stews, broths, liquid desserts, chili (dish), pudding → bowl
        if lower.contains("soup") || lower.contains("stew") || lower.contains("chowder") ||
           lower.contains("broth") || lower.contains("bisque") || lower.contains("payasam") ||
           lower.contains("rasam") { return fmt(servings, "bowl", "bowls") }
        if (lowerWords.contains("chili") || lowerWords.contains("chilli")) && servingSizeG > 15 &&
           !lower.contains("chili powder") && !lower.contains("chili sauce") {
            return fmt(servings, "bowl", "bowls")
        }
        if servingSizeG > 50 && (lower.contains("pudding") || lower.contains("custard") || lower.contains("mousse")) {
            return fmt(servings, "bowl", "bowls")
        }

        return "\(Int(totalG))g"
    }
}
