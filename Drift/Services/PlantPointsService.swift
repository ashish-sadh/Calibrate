import Foundation

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

    /// Classify a list of food names into plant points.
    static func calculate(from foodNames: [String]) -> PlantPoints {
        var plants: Set<String> = []
        var herbsSpices: Set<String> = []

        for name in foodNames {
            let normalized = normalize(name)
            if isHerbOrSpice(normalized) {
                herbsSpices.insert(normalized)
            } else if isPlantFood(normalized) {
                plants.insert(normalized)
            }
        }

        return PlantPoints(
            uniquePlants: plants.sorted(),
            uniqueHerbsSpices: herbsSpices.sorted()
        )
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

    // MARK: - Normalization

    private static func normalize(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "(cooked)", with: "")
            .replacingOccurrences(of: "(raw)", with: "")
            .replacingOccurrences(of: "(baked)", with: "")
            .replacingOccurrences(of: "(boiled)", with: "")
            .replacingOccurrences(of: "(steamed)", with: "")
            .replacingOccurrences(of: "(roasted)", with: "")
            .replacingOccurrences(of: "(grilled)", with: "")
            .replacingOccurrences(of: "(fried)", with: "")
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

        // Whole Grains
        "oats", "oatmeal", "overnight oats", "rice", "chawal",
        "brown rice", "quinoa", "barley", "jau", "millet", "bajra",
        "jowar", "sorghum", "ragi", "nachni", "finger millet",
        "amaranth", "rajgira", "buckwheat", "kuttu", "bulgur",
        "couscous", "farro", "freekeh", "wheat", "atta", "roti",
        "chapati", "paratha", "whole wheat", "multigrain",
        "poha", "flattened rice", "dosa", "idli", "upma",
        "cornmeal", "polenta", "pasta",

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

    /// Category names from the food DB that are clearly plant-based.
    private static let plantCategories: Set<String> = [
        "fruits", "vegetables", "nuts & seeds",
    ]

    private static func isPlantFood(_ name: String) -> Bool {
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
