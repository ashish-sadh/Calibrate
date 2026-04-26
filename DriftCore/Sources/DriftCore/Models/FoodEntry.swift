import Foundation
import GRDB

public struct FoodEntry: Identifiable, Codable, Sendable {
    public var id: Int64?
    public var mealLogId: Int64      // kept for backwards compat (legacy FK to meal_log)
    public var foodId: Int64?        // nil if quick-add
    public var foodName: String
    public var servingSizeG: Double
    public var servings: Double
    public var calories: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var fiberG: Double
    public var createdAt: String
    public var loggedAt: String
    public var date: String?         // "YYYY-MM-DD" — which day this belongs to
    public var mealType: String?     // "breakfast" | "lunch" | "dinner" | "snack"
    public var sodiumMg: Double?     // nullable — absent for pre-v35 entries; COALESCE to 0
    public var sugarG: Double?       // nullable — absent for pre-v35 entries; COALESCE to 0

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
        case sodiumMg = "sodium_mg"
        case sugarG = "sugar_g"
    }

    public init(
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
        mealType: String? = nil,
        sodiumMg: Double? = nil,
        sugarG: Double? = nil
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
        self.sodiumMg = sodiumMg
        self.sugarG = sugarG
    }

    /// Convenience init that copies all macro/micronutrient fields from a Food at log-time.
    public init(food: Food, servings: Double, date: String? = nil, mealType: String? = nil) {
        self.init(
            foodId: food.id,
            foodName: food.name,
            servingSizeG: food.servingSize,
            servings: servings,
            calories: food.calories,
            proteinG: food.proteinG,
            carbsG: food.carbsG,
            fatG: food.fatG,
            fiberG: food.fiberG,
            date: date,
            mealType: mealType,
            sodiumMg: food.sodiumMg,
            sugarG: food.sugarG
        )
    }

    /// Total calories for this entry (per-serving * servings).
    public var totalCalories: Double { calories * servings }
    public var totalProtein: Double { proteinG * servings }
    public var totalCarbs: Double { carbsG * servings }
    public var totalFat: Double { fatG * servings }
    public var totalFiber: Double { fiberG * servings }
    public var totalSodium: Double { (sodiumMg ?? 0) * servings }
    public var totalSugar: Double { (sugarG ?? 0) * servings }
}

extension FoodEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "food_entry"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension FoodEntry {
    /// Human-readable portion text: "2 eggs", "200g", etc.
    public var portionText: String {
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
        if lower.contains("bhakri") { return fmt(servings, "bhakri", "bhakris") }
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
        if lower.contains("laddu") || lower.contains("laddoo") || lower.contains("ladoo") ||
           lower.contains("barfi") || lower.contains("burfi") || lower.contains("jalebi") ||
           lower.contains("rasgulla") || lower.contains("modak") || lower.contains("peda") ||
           lower.contains("gujiya") || lower.contains("kaju katli") ||
           lower.contains("kalakand") || lower.contains("mysore pak") || lower.contains("sandesh") ||
           lower.contains("malpua") || lower.contains("soan papdi") || lower.contains("bebinca") ||
           lower.contains("kozhukattai") || lower.contains("thekua") || lower.contains("baklava") {
            return fmt(servings, "piece", "pieces")
        }
        // Indian snack pieces
        if lower.contains("omelette") || lower.contains("omelet") || lower.contains("frittata") {
            return fmt(servings, "omelette", "omelettes")
        }
        if lower.contains("scrambled") || lower.contains("bhurji") { return fmt(servings, "piece", "pieces") }
        if lower.contains("khakhra") { return fmt(servings, "khakhra", "khakhras") }
        if lower.contains("dhokla") || lower.contains("khaman") || lower.contains("fafda") ||
           lower.contains("handvo") || lower.contains("chilla") || lower.contains("cheela") {
            return fmt(servings, "piece", "pieces")
        }
        if lower.contains("pav bhaji") || lower.contains("misal") {
            return fmt(servings, "bowl", "bowls")
        }
        // Indian crispy snack pieces
        if lower.contains("chakli") || lower.contains("murukku") || lower.contains("mathri") ||
           lower.contains("bhakarwadi") || lower.contains("namak pare") || lower.contains("shakarpara") ||
           lower.contains("shakkar pare") || lower.contains("seedai") || lower.contains("chikki") {
            return fmt(servings, "piece", "pieces")
        }
        // Aloo tikki (potato patty) — piece
        if lower.contains("tikki") { return fmt(servings, "piece", "pieces") }
        // Bhujia (loose crispy snack) — cup
        if lower.contains("bhujia") { return fmt(servings, "cup", "cups") }
        // Loose Indian snack mixes — cup
        if lower.contains("murmura") ||
           (lower.contains("sev") && !lower.contains("puri")) ||
           lower.contains("chivda") || lower.contains("namkeen") { return fmt(servings, "cup", "cups") }
        // Ancient/whole grains (cooked) — cup
        if lower.contains("barley") || lower.contains("bulgur") || lower.contains("farro") ||
           lower.contains("freekeh") || lower.contains("millet") || lower.contains("sorghum") ||
           lower.contains("teff") || lower.contains("amaranth") { return fmt(servings, "cup", "cups") }
        // Flours and meals — cup
        if lower.contains("besan") || lower.contains("bajra") || lower.contains("maida") ||
           lower.contains("ragi") || lower.contains("jowar") { return fmt(servings, "cup", "cups") }
        if lower.contains("nugget") { return fmt(servings, "nugget", "nuggets") }
        if lower.contains("wing") && servingSizeG < 100 { return fmt(servings, "wing", "wings") }
        if lower.contains("strip") && servingSizeG < 50 { return fmt(servings, "strip", "strips") }
        if lower.contains("link") && servingSizeG < 100 { return fmt(servings, "link", "links") }
        // Meat cuts and portions
        if lower.contains("chicken breast") || lower.contains("chicken thigh") ||
           lower.contains("chicken leg") || lower.contains("pork chop") ||
           lower.contains("lamb chop") || lower.contains("chicken lollipop") {
            return fmt(servings, "piece", "pieces")
        }
        if lower.contains("steak") && !lower.contains("sauce") { return fmt(servings, "piece", "pieces") }
        if lower.contains("slice") { return fmt(servings, "slice", "slices") }
        if lower.contains("french toast") || lower.contains("croissant") || lower.contains("danish") {
            return fmt(servings, "piece", "pieces")
        }
        if lower.contains("baguette") || lower.contains("kulcha") { return fmt(servings, "piece", "pieces") }
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
        if lower.contains("whey protein") || lower.contains("protein isolate") || lower.contains("protein concentrate") {
            return fmt(servings, "scoop", "scoops")
        }
        if lower.contains("almond butter") { return fmt(servings, "tbsp", "tbsp") }
        if lower.contains("peanut butter") || lower.contains("pb2") { return fmt(servings, "tbsp", "tbsp") }
        // Cheeses
        if lower.contains("string cheese") { return fmt(servings, "piece", "pieces") }
        if lower.contains("mozzarella stick") { return fmt(servings, "piece", "pieces") }
        if lower.contains("burrata") { return fmt(servings, "piece", "pieces") }
        if (lower.contains("cheddar") || lower.contains("mozzarella") || lower.contains("provolone") ||
            lower.contains("gruyere") || lower.contains("gouda") || lower.contains("halloumi") ||
            lower.contains("colby") || lower.contains("monterey jack") || lower.contains("pepper jack") ||
            lower.contains("swiss cheese") || lower.contains("saganaki")) &&
           !lower.contains("shredded") && !lower.contains("grated") { return fmt(servings, "slice", "slices") }
        if lower.contains("brie") || lower.contains("goat cheese") || lower.contains("mascarpone") ||
           lower.contains("ricotta") || lower.contains("quark") || lower.contains("labneh") ||
           (lower.contains("blue cheese") && !lower.contains("dressing")) { return fmt(servings, "tbsp", "tbsp") }
        if (lower.contains("syrup") && !lower.contains("cough")) || lower.contains("agave") {
            return fmt(servings, "tbsp", "tbsp")
        }
        if lower.contains("patty") || lower.contains("pattie") { return fmt(servings, "patty", "patties") }
        if lower.contains("bar") && !lower.contains("barley") && servingSizeG < 80 { return fmt(servings, "bar", "bars") }
        if lower.contains("tortilla") && servingSizeG < 80 { return fmt(servings, "tortilla", "tortillas") }
        if lower.contains("pancake") && servingSizeG < 100 { return fmt(servings, "pancake", "pancakes") }
        if lower.contains("waffle") && servingSizeG < 100 { return fmt(servings, "waffle", "waffles") }
        if lower.contains("muffin") && servingSizeG < 120 { return fmt(servings, "muffin", "muffins") }
        if lower.contains("bagel") && servingSizeG < 130 { return fmt(servings, "bagel", "bagels") }
        if lower.contains("cup") && servingSizeG > 200 { return fmt(servings, "cup", "cups") }
        // Tofu — measured by cup
        if lower.contains("tofu") { return fmt(servings, "cup", "cups") }
        if lower.contains("paneer") { return fmt(servings, "cup", "cups") }
        if lower.contains("bacon") { return fmt(servings, "strip", "strips") }
        if lower.contains("sausage") && !lower.contains("roll") { return fmt(servings, "link", "links") }
        if lower.contains("turkey") { return fmt(servings, "piece", "pieces") }
        // Shredded or grated — measured by cup
        if lower.contains("shredded") || lower.contains("grated") { return fmt(servings, "cup", "cups") }
        // Mushrooms: portobello by piece, others by cup
        if lower.contains("portobello") || lower.contains("portabella") { return fmt(servings, "piece", "pieces") }
        if lower.contains("mushroom") { return fmt(servings, "cup", "cups") }
        // Standalone pav (bread roll)
        let lowerWords = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        if lowerWords.contains("pav") { return fmt(servings, "pav", "pavs") }
        // Pho and ramen — bowl
        if lower.contains("pho") || lower.contains("ramen") || lower.contains("ramyeon") {
            return fmt(servings, "bowl", "bowls")
        }
        // Aloo Indian sabzis — bowl (tikki already caught above)
        if lower.contains("aloo") && !lower.contains("tikki") && !lower.contains("bhujia") &&
           !lower.contains("puri") { return fmt(servings, "bowl", "bowls") }
        // Keema, haleem, nihari — bowl
        if lower.contains("keema") || lower.contains("haleem") || lower.contains("nihari") {
            return fmt(servings, "bowl", "bowls")
        }
        // Asian stir-fry and noodle dishes — bowl
        if lower.contains("pad thai") || lower.contains("pad see ew") || lower.contains("pad kra pao") ||
           lower.contains("general tso") || lower.contains("kung pao") || lower.contains("sweet and sour") ||
           lower.contains("sesame chicken") || lower.contains("char siu") ||
           lower.contains("lo mein") || lower.contains("chow mein") ||
           lower.contains("bibimbap") || lower.contains("japchae") ||
           lower.contains("jajangmyeon") || lower.contains("jjajangmyeon") || lower.contains("dakgalbi") ||
           lower.contains("nasi goreng") || lower.contains("nasi lemak") || lower.contains("pancit") ||
           lower.contains("kare-kare") || lower.contains("sinigang") || lower.contains("sisig") ||
           lower.contains("tteokbokki") || lower.contains("okonomiyaki") || lower.contains("cao lau") ||
           lower.contains("bun cha") || lower.contains("bun bo") || lower.contains("thukpa") ||
           lower.contains("bibim naengmyeon") || lower.contains("bun thit nuong") {
            return fmt(servings, "bowl", "bowls")
        }
        // South Indian and regional Indian dishes — bowl
        if lower.contains("avial") || lower.contains("aviyal") || lower.contains("thoran") ||
           lower.contains("poriyal") || lower.contains("kootu") || lower.contains("olan") ||
           lower.contains("bisi bele") || lower.contains("bisibele") ||
           lower.contains("zunka") || lower.contains("pithla") || lower.contains("galho") ||
           lower.contains("kosha") || lower.contains("laal maas") || lower.contains("eromba") ||
           lower.contains("masor tenga") || lower.contains("shorshe") || lower.contains("gongura") ||
           lower.contains("meen kuzhambu") || lower.contains("doi maach") || lower.contains("fish molee") ||
           lower.contains("chettinad") || lower.contains("chicken handi") || lower.contains("chicken adobo") {
            return fmt(servings, "bowl", "bowls")
        }
        // Stir-fry dishes, rendang — bowl
        if (lower.contains("stir fry") || lower.contains("stir-fry")) && !lower.contains("vegetable blend") {
            return fmt(servings, "bowl", "bowls")
        }
        if lower.contains("rendang") { return fmt(servings, "bowl", "bowls") }
        // Fajitas, bulgogi, Korean/African dishes — bowl
        if lower.contains("fajita") || lower.contains("bulgogi") || lower.contains("jerk chicken") ||
           lower.contains("peri peri") || lower.contains("piri piri") || lower.contains("tocino") ||
           lower.contains("arroz con pollo") || lower.contains("bunny chow") || lower.contains("bobotie") ||
           lower.contains("kitfo") || lower.contains("tibs") || lower.contains("doro wat") ||
           lower.contains("shiro wat") || lower.contains("suya") ||
           lower.contains("galbi") || lower.contains("samgyeopsal") || lower.contains("dakgui") {
            return fmt(servings, "bowl", "bowls")
        }
        // Fried/baked finger foods — piece
        if lower.contains("empanada") || lower.contains("calzone") || lower.contains("chimichanga") ||
           lower.contains("tamale") || lower.contains("arepa") || lower.contains("pupusa") ||
           lower.contains("arancini") || lower.contains("bao bun") || lower.contains("steamed bao") ||
           lower.contains("tostada") || lower.contains("corn dog") ||
           lower.contains("gyoza") || lower.contains("takoyaki") || lower.contains("kibbeh") ||
           lower.contains("dolma") || lower.contains("stuffed grape") || lower.contains("spanakopita") ||
           lower.contains("bruschetta") || lower.contains("onion ring") || lower.contains("cannoli") ||
           lower.contains("churros") || lower.contains("lumpia") || lower.contains("injera") {
            return fmt(servings, "piece", "pieces")
        }
        // Casserole, loaf, and slice desserts — slice
        if lower.contains("meatloaf") || lower.contains("lasagna") || lower.contains("moussaka") ||
           lower.contains("cottage pie") || lower.contains("shepherd") ||
           lower.contains("cheesecake") || lower.contains("tiramisu") || lower.contains("key lime pie") ||
           lower.contains("tres leches") || lower.contains("pumpkin pie") || lower.contains("peach cobbler") {
            return fmt(servings, "slice", "slices")
        }
        // Cup/bowl-served desserts — piece
        if lower.contains("panna cotta") || lower.contains("funnel cake") || lower.contains("bingsu") {
            return fmt(servings, "piece", "pieces")
        }
        // Pulled/shredded slow-cooked meats — cup
        if lower.contains("carnitas") || lower.contains("barbacoa") || lower.contains("pulled pork") ||
           lower.contains("al pastor") { return fmt(servings, "cup", "cups") }
        // Brisket, ribs — piece
        if lower.contains("brisket") || lower.contains("ribs") { return fmt(servings, "piece", "pieces") }
        // Popcorn — cup
        if lower.contains("popcorn") { return fmt(servings, "cup", "cups") }
        // Corn on the cob or elote — piece; other corn — cup
        if lower.contains("corn on the cob") || lower.contains("elote") { return fmt(servings, "piece", "pieces") }
        if lower.contains("corn") && !lower.contains("chip") && !lower.contains("dog") &&
           !lower.contains("flake") && !lower.contains("popcorn") { return fmt(servings, "cup", "cups") }
        // Pasta and noodle dishes — cup
        if lower.contains("pasta") || lower.contains("spaghetti") || lower.contains("penne") ||
           lower.contains("macaroni") || lower.contains("fettuccine") || lower.contains("linguine") ||
           lower.contains("fusilli") || lower.contains("rigatoni") || lower.contains("noodle") ||
           lower.contains("mac and cheese") || lower.contains("mac & cheese") ||
           lower.contains("carbonara") || lower.contains("cacio e pepe") || lower.contains("gnocchi") {
            return fmt(servings, "cup", "cups")
        }
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
        if lower.contains("mashed potato") { return fmt(servings, "cup", "cups") }
        if lower.contains("cottage cheese") { return fmt(servings, "cup", "cups") }
        if lower.contains("couscous") { return fmt(servings, "cup", "cups") }
        if lower.contains("bowl") { return fmt(servings, "bowl", "bowls") }
        if lower.contains("potato") && !lower.contains("chip") && !lower.contains("fries") &&
           !lower.contains("mashed") && !lower.contains("sweet") {
            return fmt(servings, "piece", "pieces")
        }
        // Leafy greens — cup
        if lower.contains("arugula") || lower.contains("romaine") ||
           (lower.contains("lettuce") && !lower.contains("taco")) { return fmt(servings, "cup", "cups") }
        if lower.contains("broccoli") || lower.contains("cauliflower") || lower.contains("asparagus") ||
           lower.contains("green bean") || lower.contains("edamame") ||
           lower.contains("kale") || (lower.contains("spinach") && !lower.contains("artichoke") && !lower.contains("dip")) {
            return fmt(servings, "cup", "cups")
        }
        if lower.contains("zucchini") || lower.contains("courgette") { return fmt(servings, "piece", "pieces") }
        if lower.contains("eggplant") || lower.contains("brinjal") { return fmt(servings, "piece", "pieces") }
        // Salads — bowl (dressings already matched by condiment rules and show as grams)
        if lower.contains("salad") && !lower.contains("dressing") {
            return fmt(servings, "bowl", "bowls")
        }

        // Fast food items by brand name — piece
        if lower.contains("big mac") || lower.contains("mcdouble") || lower.contains("mcchicken") ||
           lower.contains("filet-o-fish") || lower.contains("quarter pounder") ||
           lower.contains("whopper") || lower.contains("veg whopper") || lower.contains("dave's single") {
            return fmt(servings, "piece", "pieces")
        }
        // Liquid foods (coffee drinks, spirits, Indian drinks) — ml
        if lower.contains("latte") || lower.contains("cappuccino") || lower.contains("espresso") ||
           lower.contains("macchiato") || lower.contains("frappuccino") || lower.contains("americano") ||
           lower.contains("cold brew") || lower.contains("matcha latte") ||
           lower.contains("aam panna") || lower.contains("thandai") || lower.contains("jaljeera") ||
           lower.contains("nimbu pani") || lower.contains("nimbu soda") || lower.contains("shikanji") ||
           lower.contains("rooh afza") || lower.contains("falooda") || lower.contains("kahwa") ||
           lower.contains("horchata") || lower.contains("margarita") ||
           lower.contains("bcaa drink") || lower.contains("electrolyte drink") {
            let totalMl = servingSizeG * servings
            return totalMl == Double(Int(totalMl)) ? "\(Int(totalMl))ml" : String(format: "%.0fml", totalMl)
        }

        // Fish fillets — single-serve piece (ss > 70 excludes tiny garnish/topping amounts)
        let lowerWordSet = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        if (lower.contains("salmon") || lower.contains("tilapia") || lower.contains("halibut") ||
            lower.contains("sea bass") || lower.contains("seabass") || lower.contains("snapper") ||
            lower.contains("mahi") || lower.contains("swordfish") || lower.contains("mackerel") ||
            lower.contains("trout") || lower.contains("fillet") ||
            lowerWordSet.contains("cod") || lowerWordSet.contains("haddock")) && servingSizeG > 70 &&
           !lower.contains("salad") && !lower.contains("roll") && !lower.contains("burger") &&
           !lower.contains("bite") {
            return fmt(servings, "piece", "pieces")
        }

        return "\(Int(totalG))g"
    }
}
