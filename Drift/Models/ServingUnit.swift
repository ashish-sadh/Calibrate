import Foundation

// MARK: - Serving Units

enum ServingUnit: String, CaseIterable, Sendable {
    case grams, cups, tablespoons, teaspoons, pieces, ml

    var label: String {
        switch self {
        case .grams: "g"
        case .cups: "cup"
        case .tablespoons: "tbsp"
        case .teaspoons: "tsp"
        case .pieces: "pc"
        case .ml: "ml"
        }
    }

    func toGrams(_ amount: Double, ingredient: RawIngredient) -> Double {
        switch self {
        case .grams: return amount
        case .cups: return amount * ingredient.gramsPerCup
        case .tablespoons: return amount * ingredient.gramsPerCup / 16
        case .teaspoons: return amount * ingredient.gramsPerCup / 48
        case .pieces: return amount * ingredient.gramsPerPiece
        case .ml: return amount
        }
    }
}

// MARK: - Raw Ingredients

enum RawIngredient: String, CaseIterable, Identifiable, Sendable {
    case rice, wheat_flour, oats, sugar, oil, butter, ghee, milk,
         chicken_raw, egg, paneer, tofu, lentils, chickpeas,
         potato, onion, tomato, spinach, banana, apple,
         peanuts, almonds, cashews, coconut, honey

    var id: String { rawValue }

    var name: String {
        switch self {
        case .rice: "Rice (raw)"; case .wheat_flour: "Wheat Flour (atta)"; case .oats: "Oats (dry)"
        case .sugar: "Sugar"; case .oil: "Oil (any)"; case .butter: "Butter"; case .ghee: "Ghee"
        case .milk: "Milk (whole)"; case .chicken_raw: "Chicken (raw)"; case .egg: "Egg"
        case .paneer: "Paneer"; case .tofu: "Tofu"; case .lentils: "Lentils/Dal (dry)"
        case .chickpeas: "Chickpeas (dry)"; case .potato: "Potato"; case .onion: "Onion"
        case .tomato: "Tomato"; case .spinach: "Spinach"; case .banana: "Banana"
        case .apple: "Apple"; case .peanuts: "Peanuts"; case .almonds: "Almonds"
        case .cashews: "Cashews"; case .coconut: "Coconut (fresh)"; case .honey: "Honey"
        }
    }

    var caloriesPer100g: Double {
        switch self {
        case .rice: 360; case .wheat_flour: 340; case .oats: 389; case .sugar: 387
        case .oil: 884; case .butter: 717; case .ghee: 900; case .milk: 62
        case .chicken_raw: 120; case .egg: 155; case .paneer: 265; case .tofu: 144
        case .lentils: 353; case .chickpeas: 364; case .potato: 77; case .onion: 40
        case .tomato: 18; case .spinach: 23; case .banana: 89; case .apple: 52
        case .peanuts: 567; case .almonds: 579; case .cashews: 553; case .coconut: 354
        case .honey: 304
        }
    }

    var proteinPer100g: Double {
        switch self {
        case .rice: 7; case .wheat_flour: 13; case .oats: 17; case .sugar: 0
        case .oil: 0; case .butter: 0.9; case .ghee: 0; case .milk: 3.2
        case .chicken_raw: 23; case .egg: 13; case .paneer: 18; case .tofu: 15
        case .lentils: 25; case .chickpeas: 19; case .potato: 2; case .onion: 1.1
        case .tomato: 0.9; case .spinach: 2.9; case .banana: 1.1; case .apple: 0.3
        case .peanuts: 26; case .almonds: 21; case .cashews: 18; case .coconut: 3.3
        case .honey: 0.3
        }
    }

    var carbsPer100g: Double {
        switch self {
        case .rice: 80; case .wheat_flour: 72; case .oats: 66; case .sugar: 100
        case .oil: 0; case .butter: 0.1; case .ghee: 0; case .milk: 4.8
        case .chicken_raw: 0; case .egg: 1.1; case .paneer: 3; case .tofu: 3
        case .lentils: 60; case .chickpeas: 61; case .potato: 17; case .onion: 9
        case .tomato: 3.9; case .spinach: 3.6; case .banana: 23; case .apple: 14
        case .peanuts: 16; case .almonds: 22; case .cashews: 30; case .coconut: 15
        case .honey: 82
        }
    }

    var fatPer100g: Double {
        switch self {
        case .rice: 0.7; case .wheat_flour: 1.5; case .oats: 7; case .sugar: 0
        case .oil: 100; case .butter: 81; case .ghee: 100; case .milk: 3.3
        case .chicken_raw: 3.6; case .egg: 11; case .paneer: 21; case .tofu: 8
        case .lentils: 1; case .chickpeas: 6; case .potato: 0.1; case .onion: 0.1
        case .tomato: 0.2; case .spinach: 0.4; case .banana: 0.3; case .apple: 0.2
        case .peanuts: 49; case .almonds: 50; case .cashews: 44; case .coconut: 33
        case .honey: 0
        }
    }

    var fiberPer100g: Double {
        switch self {
        case .rice: 1.3; case .wheat_flour: 11; case .oats: 11; case .sugar: 0
        case .oil: 0; case .butter: 0; case .ghee: 0; case .milk: 0
        case .chicken_raw: 0; case .egg: 0; case .paneer: 0; case .tofu: 1
        case .lentils: 11; case .chickpeas: 12; case .potato: 2.2; case .onion: 1.7
        case .tomato: 1.2; case .spinach: 2.2; case .banana: 2.6; case .apple: 2.4
        case .peanuts: 8.5; case .almonds: 12; case .cashews: 3; case .coconut: 9
        case .honey: 0.2
        }
    }

    var gramsPerCup: Double {
        switch self {
        case .rice: 185; case .wheat_flour: 120; case .oats: 80; case .sugar: 200
        case .oil: 218; case .butter: 227; case .ghee: 218; case .milk: 244
        case .chicken_raw: 140; case .egg: 243; case .paneer: 150; case .tofu: 126
        case .lentils: 190; case .chickpeas: 164; case .potato: 150; case .onion: 160
        case .tomato: 180; case .spinach: 30; case .banana: 150; case .apple: 125
        case .peanuts: 146; case .almonds: 143; case .cashews: 137; case .coconut: 80
        case .honey: 340
        }
    }

    var gramsPerPiece: Double {
        switch self {
        case .egg: 50; case .banana: 120; case .apple: 180; case .potato: 150
        case .onion: 110; case .tomato: 120
        default: 100
        }
    }

    var typicalUnit: ServingUnit {
        switch self {
        case .egg, .banana, .apple: .pieces
        case .oil, .butter, .ghee, .honey: .tablespoons
        case .milk: .ml
        default: .grams
        }
    }
}

// MARK: - Food-relative conversion

extension ServingUnit {
    /// Convert amount to grams, using the food's serving size as reference for "pieces" (servings).
    func toGrams(_ amount: Double, foodServingSize: Double) -> Double {
        switch self {
        case .grams: return amount
        case .pieces: return amount * foodServingSize
        case .cups: return amount * 240
        case .tablespoons: return amount * 15
        case .teaspoons: return amount * 5
        case .ml: return amount
        }
    }
}

// MARK: - Smart Food Units

/// Context-aware serving unit for a food item (e.g. "egg" for eggs, "tbsp" for oil).
struct FoodUnit: Hashable {
    let label: String
    let gramsEquivalent: Double

    /// Returns food-appropriate units. First unit is the most natural for this food.
    static func smartUnits(for food: Food) -> [FoodUnit] {
        let lower = food.name.lowercased()
        var units: [FoodUnit] = []

        let primary = primaryUnit(for: lower, servingSize: food.servingSize)
        units.append(primary)

        if primary.label != "g" {
            units.append(FoodUnit(label: "g", gramsEquivalent: 1))
        }

        let cupFoods = ["rice", "dal", "oats", "cereal", "flour", "lentil", "chickpea",
                        "rajma", "chole", "paneer", "tofu", "quinoa", "pasta", "beans",
                        "peas", "corn", "yogurt", "curd", "poha", "upma", "khichdi"]
        if cupFoods.contains(where: { lower.contains($0) }) && primary.label != "cup" {
            units.append(FoodUnit(label: "cup", gramsEquivalent: cupGrams(for: lower)))
        }

        let tbspFoods = ["sauce", "chutney", "ketchup", "mayo", "dressing", "syrup",
                         "jam", "peanut butter", "almond butter", "honey", "mustard"]
        if tbspFoods.contains(where: { lower.contains($0) }) && primary.label != "tbsp" {
            units.append(FoodUnit(label: "tbsp", gramsEquivalent: 15))
        }

        let liquidFoods = ["milk", "juice", "lassi", "buttermilk", "coconut water",
                           "smoothie", "broth", "soup", "shake"]
        if liquidFoods.contains(where: { lower.contains($0) }) {
            if primary.label != "ml" {
                units.append(FoodUnit(label: "ml", gramsEquivalent: 1))
            }
            if primary.label != "cup" && !units.contains(where: { $0.label == "cup" }) {
                units.append(FoodUnit(label: "cup", gramsEquivalent: 240))
            }
        }

        // Nuts — add per-piece count unit
        if lower.contains("almond") && !lower.contains("milk") && !lower.contains("butter") && !lower.contains("flour") {
            units.append(FoodUnit(label: "almond", gramsEquivalent: 1.2))
        }
        if lower.contains("cashew") && !lower.contains("butter") {
            units.append(FoodUnit(label: "cashew", gramsEquivalent: 1.5))
        }
        if lower.contains("pistachio") {
            units.append(FoodUnit(label: "pistachio", gramsEquivalent: 0.6))
        }
        if lower.contains("walnut") {
            units.append(FoodUnit(label: "half", gramsEquivalent: 2.5))
        }

        return units
    }

    private static func primaryUnit(for name: String, servingSize: Double) -> FoodUnit {
        let ss = servingSize > 0 ? servingSize : 100

        // Countable items
        if name.contains("egg") && ss < 80 { return FoodUnit(label: "egg", gramsEquivalent: ss) }
        if name.contains("meatball") && ss < 50 { return FoodUnit(label: "meatball", gramsEquivalent: ss) }
        if name.contains("roti") || name.contains("chapati") || name.contains("naan") || name.contains("paratha") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        if name.contains("dosa") || name.contains("idli") || name.contains("vada") ||
           name.contains("samosa") || name.contains("pakora") || name.contains("momo") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        if name.contains("banana") && ss < 160 { return FoodUnit(label: "banana", gramsEquivalent: ss) }
        if name.contains("apple") && ss < 250 { return FoodUnit(label: "apple", gramsEquivalent: ss) }
        if name.contains("orange") && ss < 200 { return FoodUnit(label: "orange", gramsEquivalent: ss) }
        if name.contains("cookie") || name.contains("biscuit") { return FoodUnit(label: "piece", gramsEquivalent: ss) }
        if name.contains("scoop") { return FoodUnit(label: "scoop", gramsEquivalent: ss) }
        // Nuts — show count as secondary unit
        if name.contains("almond") && !name.contains("milk") && !name.contains("butter") && !name.contains("flour") {
            return FoodUnit(label: "serving", gramsEquivalent: ss)
        }
        if name.contains("cashew") && !name.contains("butter") { return FoodUnit(label: "serving", gramsEquivalent: ss) }
        if name.contains("pistachio") { return FoodUnit(label: "serving", gramsEquivalent: ss) }
        if name.contains("walnut") { return FoodUnit(label: "serving", gramsEquivalent: ss) }

        // Tablespoon items
        if name.contains("oil") || name.contains("ghee") { return FoodUnit(label: "tbsp", gramsEquivalent: 15) }
        if name.contains("butter") && !name.contains("peanut") && !name.contains("almond") && !name.contains("paneer") {
            return FoodUnit(label: "tbsp", gramsEquivalent: 14)
        }

        // Liquid items
        if name.contains("milk") || name.contains("juice") || name.contains("lassi") ||
           name.contains("chai") || name.contains("tea") || name.contains("coffee") ||
           name.contains("buttermilk") {
            return FoodUnit(label: "ml", gramsEquivalent: 1)
        }

        return FoodUnit(label: "serving", gramsEquivalent: ss)
    }

    private static func cupGrams(for name: String) -> Double {
        if name.contains("rice") { return 185 }
        if name.contains("oats") { return 80 }
        if name.contains("flour") || name.contains("atta") { return 120 }
        if name.contains("dal") || name.contains("lentil") { return 200 }
        if name.contains("chickpea") || name.contains("chole") || name.contains("rajma") { return 164 }
        if name.contains("paneer") { return 150 }
        if name.contains("yogurt") || name.contains("curd") || name.contains("dahi") { return 245 }
        if name.contains("poha") { return 60 }
        return 240
    }
}
