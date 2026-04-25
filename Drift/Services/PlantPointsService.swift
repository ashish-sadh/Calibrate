import Foundation
import DriftCore

/// Tracks plant diversity using the "30 plants per week" framework.
/// 1 point per unique plant food, 0.25 per unique herb/spice.
enum PlantPointsService {

    // MARK: - Public API

    struct PlantPoints {
        let uniquePlants: [String]       // full-point plant names
        let uniqueHerbsSpices: [String]  // quarter-point herb/spice names
        var fullPoints: Double { Double(uniquePlants.count) }
        var quarterPoints: Double { Double(uniqueHerbsSpices.count) * 0.25 }
        var total: Double { fullPoints + quarterPoints }
        var plantCount: Int { uniquePlants.count + uniqueHerbsSpices.count }
    }

    /// Top-level type lives in DriftCore so AppDatabase can return it.
    typealias FoodItem = PlantPointsFoodItem

    /// Classify food items into plant points with NOVA-aware logic.
    /// - NOVA 1-2: count directly
    /// - NOVA 3: skip food name, count ingredients individually
    /// - NOVA 4: skip entirely (food + ingredients)
    /// - No ingredients + no NOVA: classify by name (backwards compat)
    static func calculate(from items: [FoodItem]) -> PlantPoints {
        var plants: Set<String> = []
        var herbsSpices: Set<String> = []

        for item in items {
            // NOVA 4: ultra-processed — skip entirely
            if item.novaGroup == 4 { continue }

            // Determine which names to classify
            let namesToClassify: [String]
            if item.novaGroup == 3, let ingredients = item.ingredients, !ingredients.isEmpty {
                // NOVA 3: processed — skip food name, use ingredients
                namesToClassify = ingredients
            } else if let ingredients = item.ingredients, ingredients.count > 1 {
                // Has ingredients list — use it (more granular)
                namesToClassify = ingredients
            } else {
                // Simple food or no ingredients — use name
                namesToClassify = [item.name]
            }

            let expanded = expandSpiceBlends(namesToClassify)
            for name in expanded {
                let normalized = resolveAlias(normalize(name))
                if isHerbOrSpice(normalized) {
                    herbsSpices.insert(normalized)
                } else if let plantName = matchingPlantKeyword(normalized) {
                    plants.insert(plantName)  // insert the keyword, not the full food name
                }
            }
        }

        return PlantPoints(
            uniquePlants: plants.sorted(),
            uniqueHerbsSpices: herbsSpices.sorted()
        )
    }

    /// Legacy: classify a list of plain food names (backwards compat for tests/simple callers).
    static func calculate(from foodNames: [String]) -> PlantPoints {
        calculate(from: foodNames.map { FoodItem(name: $0, ingredients: nil, novaGroup: nil) })
    }

    /// Classify a single food name.
    enum PlantCategory {
        case plant, herbSpice, notPlant
    }

    static func classify(_ foodName: String) -> PlantCategory {
        let n = normalize(foodName)
        if isHerbOrSpice(n) { return .herbSpice }
        if isPlantFood(n) { return .plant }
        return .notPlant
    }

    // MARK: - Alias Normalization (Hindi → English canonical names)

    private static let plantAliases: [String: String] = [
        // Vegetables
        "palak": "spinach", "aloo": "potato", "tamatar": "tomato",
        "pyaaz": "onion", "gobi": "cauliflower", "gajar": "carrot",
        "bhindi": "okra", "baingan": "eggplant", "matar": "peas",
        "lehsun": "garlic", "adrak": "ginger", "kheera": "cucumber",
        "kaddu": "pumpkin", "lauki": "bottle gourd", "turai": "ridge gourd",
        "karela": "bitter gourd", "mooli": "radish", "shalgam": "turnip",
        "shimla mirch": "bell pepper", "patta gobi": "cabbage",
        "chukandar": "beetroot", "shakarkandi": "sweet potato",
        "makka": "corn", "kachha kela": "raw banana",
        // Spices
        "haldi": "turmeric", "jeera": "cumin", "dalchini": "cinnamon",
        "elaichi": "cardamom", "laung": "cloves", "dhania": "coriander",
        "saunf": "fennel", "methi": "fenugreek", "rai": "mustard seeds",
        "hing": "asafoetida", "kesar": "saffron", "ajwain": "carom seeds",
        "kalonji": "nigella seeds", "jaiphal": "nutmeg", "til": "sesame seeds",
        // Fruits
        "nariyal": "coconut", "aam": "mango", "kela": "banana",
        "seb": "apple", "angoor": "grapes", "santara": "orange",
        // Legumes
        "rajma": "kidney beans", "chana": "chickpeas", "urad": "black gram",
        "moong": "mung bean", "masoor": "red lentils", "toor": "pigeon pea",
        // Dairy (non-plant — alias for consistency)
        "dahi": "yogurt", "paneer": "cottage cheese",
    ]

    private static func resolveAlias(_ name: String) -> String {
        // Check exact match first
        if let canonical = plantAliases[name] { return canonical }
        // Check if name starts with an alias (e.g. "palak paneer" → "spinach")
        for (alias, canonical) in plantAliases {
            if name.hasPrefix(alias + " ") { return canonical }
        }
        return name
    }

    // MARK: - Normalization

    private static func normalize(_ name: String) -> String {
        // Strip all parentheticals: "(cooked)", "(half)", "(medium)", "(2 pieces)", etc.
        name.lowercased()
            .replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Herb & Spice Detection

    private static let herbs: Set<String> = [
        "basil", "cilantro", "coriander leaves", "parsley", "mint", "rosemary",
        "oregano", "thyme", "dill", "sage", "chives", "tarragon", "bay leaf",
        "bay leaves", "curry leaves", "lemongrass", "marjoram"
    ]

    private static let spices: Set<String> = [
        "turmeric", "haldi", "cumin", "jeera", "cinnamon", "dalchini",
        "black pepper", "pepper", "cardamom", "elaichi", "cloves", "laung",
        "coriander powder", "coriander", "dhania", "paprika", "chili powder",
        "red chili", "cayenne", "nutmeg", "jaiphal", "fennel", "saunf",
        "fenugreek", "methi", "mustard seeds", "rai", "asafoetida", "hing",
        "star anise", "saffron", "kesar", "garam masala", "chaat masala",
        "ginger powder", "garlic powder", "onion powder", "ajwain",
        "carom seeds", "nigella seeds", "kalonji", "poppy seeds",
        "sesame seeds", "til"  // sesame as spice quantity
    ]

    /// Spice blends → expand into individual spices for more accurate counting.
    private static let spiceBlends: [String: [String]] = [
        "garam masala": ["cumin", "coriander", "cardamom", "cloves", "pepper"],
        "chaat masala": ["cumin", "coriander", "black salt", "pepper", "ginger powder"],
        "curry powder": ["turmeric", "cumin", "coriander", "fenugreek", "pepper"],
        "pumpkin spice": ["cinnamon", "nutmeg", "cloves", "ginger powder"],
        "chinese five spice": ["star anise", "cloves", "cinnamon", "pepper", "fennel"],
        "italian seasoning": ["oregano", "basil", "thyme", "rosemary", "sage"],
        "herbs de provence": ["thyme", "rosemary", "oregano", "basil", "sage"],
        "taco seasoning": ["cumin", "paprika", "chili powder", "oregano", "garlic powder"],
        "berbere": ["paprika", "fenugreek", "coriander", "cardamom", "pepper"],
        "ras el hanout": ["cumin", "coriander", "turmeric", "cinnamon", "pepper"],
    ]

    /// Expand spice blend names into individual spices.
    static func expandSpiceBlends(_ names: [String]) -> [String] {
        var result: [String] = []
        for name in names {
            let lower = name.lowercased()
            if let blend = spiceBlends[lower] {
                result.append(contentsOf: blend)
            } else {
                result.append(name)
            }
        }
        return result
    }

    private static func isHerbOrSpice(_ name: String) -> Bool {
        // Exact match or contained as primary ingredient
        for herb in herbs {
            if name == herb || name.hasPrefix(herb + " ") || name.hasSuffix(" " + herb) {
                return true
            }
        }
        for spice in spices {
            if name == spice || name.hasPrefix(spice + " ") || name.hasSuffix(" " + spice) {
                return true
            }
        }
        return false
    }

    // MARK: - Plant Food Detection

    /// Keywords that strongly indicate a plant food.
    private static let plantKeywords: Set<String> = [
        // Fruits
        "banana", "apple", "mango", "orange", "grapes", "grape", "watermelon",
        "papaya", "pineapple", "strawberry", "strawberries", "blueberry",
        "blueberries", "raspberry", "raspberries", "blackberry", "blackberries",
        "cherry", "cherries", "peach", "pear", "plum", "kiwi", "pomegranate",
        "guava", "lychee", "coconut", "fig", "dates", "date", "apricot",
        "cantaloupe", "honeydew", "cranberry", "cranberries", "avocado",
        "lemon", "lime", "grapefruit", "tangerine", "clementine", "jackfruit",
        "dragonfruit", "passion fruit", "persimmon", "mulberry", "gooseberry",

        // Vegetables
        "spinach", "palak", "broccoli", "cauliflower", "gobi", "carrot",
        "gajar", "tomato", "tamatar", "potato", "aloo", "sweet potato",
        "shakarkandi", "onion", "pyaaz", "garlic", "lehsun", "ginger",
        "adrak", "cabbage", "patta gobi", "lettuce", "kale", "bell pepper",
        "capsicum", "shimla mirch", "zucchini", "cucumber", "kheera",
        "eggplant", "baingan", "brinjal", "okra", "bhindi", "lady finger",
        "peas", "matar", "green beans", "french beans", "corn", "makka",
        "beetroot", "chukandar", "radish", "mooli", "turnip", "shalgam",
        "pumpkin", "kaddu", "bottle gourd", "lauki", "ridge gourd", "turai",
        "bitter gourd", "karela", "drumstick", "moringa", "mushroom",
        "asparagus", "artichoke", "celery", "leek", "bok choy", "arugula",
        "watercress", "collard greens", "swiss chard", "brussels sprouts",
        "snap peas", "snow peas", "edamame", "bean sprouts", "bamboo shoots",
        "taro", "yam", "plantain", "jackfruit", "raw banana", "kachha kela",
        "methi leaves", "fenugreek leaves", "sarson", "mustard greens",
        "bathua", "amaranth leaves", "colocasia", "arbi",

        // Legumes & Pulses
        "dal", "daal", "lentil", "lentils", "chickpea", "chickpeas",
        "chana", "chole", "rajma", "kidney bean", "kidney beans",
        "black bean", "black beans", "moong", "masoor", "toor", "urad",
        "moth", "lobiya", "cowpea", "pigeon pea", "pinto bean",
        "navy bean", "lima bean", "soybean", "tofu", "tempeh",
        "hummus", "falafel", "sprouts",

        // Whole Grains (raw/minimally processed only — not bread, pasta, roti)
        "oats", "oatmeal", "overnight oats", "rice", "chawal",
        "brown rice", "quinoa", "barley", "jau", "millet", "bajra",
        "jowar", "sorghum", "ragi", "nachni", "finger millet",
        "amaranth", "rajgira", "buckwheat", "kuttu", "bulgur",
        "couscous", "farro", "freekeh", "wheat berries", "whole wheat",
        "poha", "flattened rice",
        "cornmeal", "polenta",

        // Nuts
        "almond", "almonds", "walnut", "walnuts", "cashew", "cashews",
        "peanut", "peanuts", "peanut butter", "pistachio", "pistachios",
        "pecan", "pecans", "macadamia", "brazil nut", "hazelnut",
        "hazelnuts", "pine nut", "pine nuts", "chestnut",

        // Seeds (as food, not spice quantity)
        "chia seeds", "chia", "flaxseed", "flax seeds", "alsi",
        "sunflower seeds", "pumpkin seeds", "hemp seeds",
    ]

    /// Foods that contain plant keywords but aren't primarily plant-based.
    private static let nonPlantOverrides: Set<String> = [
        "chicken", "turkey", "beef", "pork", "lamb", "mutton", "goat",
        "fish", "salmon", "tuna", "shrimp", "prawn", "crab", "lobster",
        "scallop", "egg", "eggs", "whey", "casein", "paneer", "cheese",
        "butter", "ghee", "cream", "milk", "yogurt", "curd", "dahi",
        "ice cream", "chocolate", "candy", "cookie", "cake", "pastry",
        "protein powder", "protein bar", "protein shake",
        "nugget", "wing", "strip", "meatball", "sausage", "bacon",
        "steak", "ribs", "kebab", "tikka", "tandoori",
    ]

    /// Processed plant-derived foods that don't count as whole plants.
    private static let processedPlantFoods: Set<String> = [
        "bread", "wheat bread", "white bread", "whole wheat bread",
        "naan", "roti", "chapati", "paratha", "puri", "kulcha",
        "pasta", "spaghetti", "macaroni", "noodles", "ramen", "udon",
        "tortilla", "wrap", "pita", "croutons", "baguette",
        "dosa", "idli", "upma", "uttapam",
        "flour", "maida", "atta", "wheat", "semolina", "suji",
        "chips", "crackers", "cookie", "biscuit",
        "juice", "soda", "syrup",
        "cereal", "granola bar",
        "toasted bread", "toast",
    ]

    /// Category names from the food DB that are clearly plant-based.
    private static let plantCategories: Set<String> = [
        "fruits", "vegetables", "nuts & seeds",
    ]

    /// Returns the matching plant keyword if found (e.g. "avocado toast" → "avocado"), or nil.
    private static func matchingPlantKeyword(_ name: String) -> String? {
        guard isPlantFood(name) else { return nil }
        // If the name IS a keyword, return as-is
        if plantKeywords.contains(name) { return name }
        // Otherwise find which keyword matched
        let words = Set(name.components(separatedBy: .whitespaces))
        if let match = words.first(where: { plantKeywords.contains($0) }) { return match }
        // Multi-word keyword match
        for keyword in plantKeywords {
            if name.contains(keyword) { return keyword }
        }
        return name // fallback to full name
    }

    private static func isPlantFood(_ name: String) -> Bool {
        // Reject processed plant-derived foods (bread, pasta, naan, etc.)
        if processedPlantFoods.contains(name) { return false }

        // Reject if it matches non-plant overrides
        for keyword in nonPlantOverrides {
            if name.contains(keyword) { return false }
        }

        // Check direct keyword matches
        for keyword in plantKeywords {
            if name == keyword
                || name.hasPrefix(keyword + " ")
                || name.hasPrefix(keyword + ",")
                || name.hasSuffix(" " + keyword)
                || name.contains(" " + keyword + " ")
                || name.contains(" " + keyword + ",") {
                return true
            }
        }

        // Compound food patterns (e.g. "rice and dal", "dal makhani")
        let words = Set(name.components(separatedBy: .whitespaces))
        let plantWords = words.intersection(plantKeywords)
        if !plantWords.isEmpty { return true }

        return false
    }
}
