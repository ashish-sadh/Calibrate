import Foundation

// MARK: - Serving Units

enum ServingUnit: String, CaseIterable, Sendable {
    case grams, cups, tablespoons, teaspoons, pieces, ml, flOz

    var label: String {
        switch self {
        case .grams: "g"
        case .cups: "cup"
        case .tablespoons: "tbsp"
        case .teaspoons: "tsp"
        case .pieces: "pc"
        case .ml: "ml"
        case .flOz: "fl oz"
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
        case .flOz: return amount * 29.5735 // 1 fl oz = 29.57 ml ≈ g for water-based liquids
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
        case .flOz: return amount * 29.5735
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
        let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map { String($0) })
        var units: [FoodUnit] = []

        let primary = primaryUnit(for: lower, servingSize: food.servingSize, words: words)
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

        // Protein powder / supplements — add "scoop"
        let scoopFoods = ["protein", "whey", "casein", "isolate", "creatine", "collagen",
                          "powder", "supplement", "pre-workout", "bcaa"]
        if scoopFoods.contains(where: { lower.contains($0) }) && !units.contains(where: { $0.label == "scoop" }) {
            units.append(FoodUnit(label: "scoop", gramsEquivalent: food.servingSize > 0 ? food.servingSize : 30))
        }

        // Coffee / tea — add "cup" (240ml)
        let coffeeFoods = ["coffee", "espresso", "americano", "latte", "cappuccino", "mocha"]
        if coffeeFoods.contains(where: { lower.contains($0) }) {
            if !units.contains(where: { $0.label == "cup" }) {
                units.append(FoodUnit(label: "cup", gramsEquivalent: 240))
            }
            if !units.contains(where: { $0.label == "ml" }) {
                units.append(FoodUnit(label: "ml", gramsEquivalent: 1))
            }
        }

        // Universal: add tsp for sauces, condiments, and oils
        if tbspFoods.contains(where: { lower.contains($0) }) && !units.contains(where: { $0.label == "tsp" }) {
            units.append(FoodUnit(label: "tsp", gramsEquivalent: 5))
        }

        // Oils — add spray, ml, tsp alongside tbsp (word boundary: "boiled" contains "oil")
        if words.contains("oil") || words.contains("ghee") {
            if !units.contains(where: { $0.label == "spray" }) {
                units.append(FoodUnit(label: "spray", gramsEquivalent: 0.25)) // ~1 cal per spray
            }
            if !units.contains(where: { $0.label == "tsp" }) {
                units.append(FoodUnit(label: "tsp", gramsEquivalent: 5))
            }
            if !units.contains(where: { $0.label == "ml" }) {
                units.append(FoodUnit(label: "ml", gramsEquivalent: 1))
            }
        }

        // Vegetables & fruits — add "piece" for whole items
        let pieceFoods = ["capsicum", "pepper", "bell pepper", "onion", "tomato", "potato",
                          "carrot", "cucumber", "zucchini", "eggplant", "brinjal", "avocado",
                          "lemon", "lime", "mango", "peach", "pear", "plum", "guava",
                          "kiwi", "fig", "apricot", "corn", "beet", "turnip", "radish"]
        if pieceFoods.contains(where: { lower.contains($0) }) && primary.label != "piece" && !units.contains(where: { $0.label == "piece" }) {
            let pieceWeight = pieceGrams(for: lower)
            units.append(FoodUnit(label: "piece", gramsEquivalent: pieceWeight))
        }

        let liquidSubstrings = ["milk", "juice", "buttermilk", "coconut water",
                                "smoothie", "broth", "soup", "shake", "lemonade",
                                "soda", "cola", "kombucha", "water"]
        let isLiquid = liquidSubstrings.contains(where: { lower.contains($0) })
            || words.contains("lassi") || words.contains("tea") || words.contains("chai")
            || words.contains("latte") || words.contains("coffee") || words.contains("espresso")
        if isLiquid {
            if !units.contains(where: { $0.label == "ml" }) {
                units.append(FoodUnit(label: "ml", gramsEquivalent: 1))
            }
            if !units.contains(where: { $0.label == "fl oz" }) {
                units.append(FoodUnit(label: "fl oz", gramsEquivalent: 29.5735))
            }
            if !units.contains(where: { $0.label == "cup" }) {
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

        // Universal: include "piece" for foods where a "piece" makes sense
        // Skip for: bulk foods (nuts, grains, powder, flour, oil, butter, rice, oats)
        // and foods that already have a per-item unit (almond, cashew, egg, banana, etc.)
        let countableLabels: Set<String> = ["piece", "egg", "banana", "apple", "orange", "meatball",
                                             "slice", "almond", "cashew", "pistachio", "half"]
        let bulkFoods = ["almond", "cashew", "pistachio", "walnut", "peanut", "nut", "seed",
                         "rice", "oats", "oatmeal", "flour", "sugar", "salt", "powder",
                         "oil", "butter", "ghee", "cream", "cheese", "yogurt", "curd",
                         "dal", "lentil", "bean", "chickpea", "quinoa", "couscous",
                         "granola", "cereal", "pasta", "noodle", "sauce", "dressing",
                         "hummus", "pesto", "jam", "honey", "syrup", "mayo"]
        let isBulk = bulkFoods.contains(where: { lower.contains($0) })
        if !isBulk && !units.contains(where: { countableLabels.contains($0.label) }) {
            let pieceWeight = food.servingSize > 0 ? food.servingSize : 100
            units.append(FoodUnit(label: "piece", gramsEquivalent: pieceWeight))
        }

        return units
    }

    private static func primaryUnit(for name: String, servingSize: Double, words: Set<String> = []) -> FoodUnit {
        let ss = servingSize > 0 ? servingSize : 100

        // Countable items
        if words.contains("egg") && ss < 80 { return FoodUnit(label: "egg", gramsEquivalent: ss) }
        if name.contains("meatball") && ss < 50 { return FoodUnit(label: "meatball", gramsEquivalent: ss) }

        // Batter / dough — measured in cups (must come before dosa/idli rule)
        // Exclude consumed forms: sourdough/bread (→slice), doughnut (→piece), cookie dough (flavor)
        if name.contains("batter") || (name.contains("dough") && !name.contains("bread") &&
           !name.contains("sourdough") && !name.contains("doughnut") && !name.contains("cookie")) {
            return FoodUnit(label: "cup", gramsEquivalent: cupGrams(for: name))
        }

        if name.contains("roti") || name.contains("chapati") || name.contains("naan") || name.contains("paratha") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        if name.contains("dosa") || name.contains("idli") || name.contains("vada") ||
           name.contains("samosa") || name.contains("pakora") || name.contains("momo") ||
           name.contains("uttapam") || name.contains("kachori") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Additional Indian flatbreads
        if name.contains("puri") || name.contains("poori") || name.contains("bhatura") ||
           name.contains("bhatoora") || name.contains("thepla") || name.contains("phulka") ||
           name.contains("appam") || name.contains("pesarattu") || name.contains("adai") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Chaat and Indian snack mixes — served by bowl (must precede the puri check above)
        if name.contains("bhel") || name.contains("sev puri") || name.contains("papdi chaat") ||
           (name.contains("chaat") && !name.contains("chaat masala")) {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }

        // Indian sweets — always countable by piece
        if name.contains("gulab") || name.contains("jamun") || name.contains("laddu") ||
           name.contains("laddoo") || name.contains("barfi") || name.contains("burfi") ||
           name.contains("jalebi") || name.contains("rasgulla") || name.contains("rasmalai") ||
           name.contains("modak") || name.contains("peda") || name.contains("gujiya") ||
           name.contains("mithai") || name.contains("pinni") || name.contains("kaju katli") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Sliceable foods
        if (name.contains("bread") || name.contains("toast")) &&
           !name.contains("breadfruit") && !name.contains("breadstick") {
            return FoodUnit(label: "slice", gramsEquivalent: ss)
        }
        if name.contains("pizza") { return FoodUnit(label: "slice", gramsEquivalent: ss) }
        if name.contains("date") && !name.contains("update") { return FoodUnit(label: "piece", gramsEquivalent: ss) }
        if name.contains("tortilla") || name.contains("wrap") { return FoodUnit(label: "piece", gramsEquivalent: ss) }
        if name.contains("wing") || name.contains("nugget") || name.contains("tender") { return FoodUnit(label: "piece", gramsEquivalent: ss) }
        if name.contains("waffle") || name.contains("pancake") || name.contains("donut") || name.contains("doughnut") { return FoodUnit(label: "piece", gramsEquivalent: ss) }
        if name.contains("brownie") || name.contains("muffin") || name.contains("cupcake") { return FoodUnit(label: "piece", gramsEquivalent: ss) }
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

        // Protein powder — measured by scoop
        if name.contains("protein powder") {
            return FoodUnit(label: "scoop", gramsEquivalent: ss)
        }

        // Condiments and dips — tablespoon (before oil/ghee to avoid double-matching)
        if name.contains("ketchup") || name.contains("salsa") || name.contains("guacamole") ||
           name.contains("hummus") || name.contains("tahini") || name.contains("sriracha") ||
           name.contains("hot sauce") || name.contains("soy sauce") || name.contains("bbq sauce") ||
           name.contains("fish sauce") || name.contains("oyster sauce") || name.contains("hoisin") ||
           name.contains("teriyaki sauce") || name.contains("vinaigrette") || name.contains("relish") ||
           name.contains("aioli") || name.contains("mayo") || name.contains("mayonnaise") ||
           name.contains("ranch") || name.contains("pesto") || name.contains("chili sauce") ||
           name.contains("chutney") || name.contains("tamarind sauce") || name.contains("tzatziki") {
            return FoodUnit(label: "tbsp", gramsEquivalent: 15)
        }

        // Tablespoon items (word boundaries: "boiled" contains "oil", "butternut" contains "butter")
        if words.contains("oil") || words.contains("ghee") { return FoodUnit(label: "tbsp", gramsEquivalent: 15) }
        if words.contains("butter") && !name.contains("peanut") && !name.contains("almond") && !name.contains("paneer") {
            return FoodUnit(label: "tbsp", gramsEquivalent: 14)
        }

        // Honey, jam, jelly, marmalade — tablespoon
        if name.contains("honey") ||
           (name.contains("jam") && !name.contains("jamun")) ||
           (name.contains("jelly") && !name.contains("jellyfish")) ||
           name.contains("marmalade") {
            return FoodUnit(label: "tbsp", gramsEquivalent: 21)
        }

        // Seeds — tablespoon (chia, flax, hemp, sesame, sunflower, pumpkin, til)
        if name.contains("chia seed") || name.contains("flax seed") || name.contains("flaxseed") ||
           name.contains("hemp seed") || name.contains("sesame seed") ||
           name.contains("sunflower seed") || name.contains("pumpkin seed") ||
           (words.contains("til") && !name.contains("tilgul")) {
            return FoodUnit(label: "tbsp", gramsEquivalent: 10)
        }

        // Cream — tablespoon for heavy/cooking/fresh; cup for sour/whipped
        if name.contains("heavy cream") || name.contains("cooking cream") ||
           name.contains("fresh cream") || name.contains("double cream") ||
           name.contains("cream cheese") || name.contains("whipping cream") {
            return FoodUnit(label: "tbsp", gramsEquivalent: 15)
        }
        if name.contains("sour cream") || name.contains("whipped cream") {
            return FoodUnit(label: "cup", gramsEquivalent: 230)
        }

        // Ice cream, gelato, sorbet — scoop
        if name.contains("ice cream") || name.contains("gelato") || name.contains("sorbet") {
            return FoodUnit(label: "scoop", gramsEquivalent: ss)
        }

        // Papad — always by piece (roasted or fried crisp)
        if name.contains("papad") || name.contains("pappad") || name.contains("appalam") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Bars — measured by piece (protein bar, granola bar, energy bar, cereal bar)
        if name.contains("protein bar") || name.contains("granola bar") ||
           name.contains("energy bar") || name.contains("cereal bar") ||
           name.contains("snack bar") || (name.contains("bar") && name.contains("nut")) {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Pickle / achar — tablespoon (condiment portion)
        if name.contains("pickle") || name.contains("achar") || name.contains("achaar") {
            return FoodUnit(label: "tbsp", gramsEquivalent: 15)
        }

        // Rice — measured in cups (servingSize in DB is ~158g = 1 cup cooked)
        // Exclude rice cakes, rice paper, rice wine, rice crackers, rice noodles
        if name.contains("rice") && !name.contains("cake") && !name.contains("paper") &&
           !name.contains("wine") && !name.contains("cracker") && !name.contains("noodle") &&
           !name.contains("pudding") && !name.contains("crisp") {
            return FoodUnit(label: "cup", gramsEquivalent: cupGrams(for: name))
        }

        // Quinoa — measured in cups (like rice)
        if name.contains("quinoa") {
            return FoodUnit(label: "cup", gramsEquivalent: 185)
        }

        // Dal and cooked legumes — measured in cups
        // Word boundary on "dal"/"daal" prevents false matches on unrelated words.
        // Exclude coffee beans, jelly beans, cocoa beans.
        if words.contains("dal") || words.contains("daal") || words.contains("rajma") {
            return FoodUnit(label: "cup", gramsEquivalent: cupGrams(for: name))
        }
        if (name.contains("black bean") || name.contains("kidney bean") ||
            name.contains("pinto bean") || name.contains("navy bean") ||
            name.contains("chickpea") || name.contains("lentil") ||
            name.contains("chole") || name.contains("chana")) &&
           !name.contains("jelly") && !name.contains("cocoa") && !name.contains("coffee") &&
           !name.contains("masala") && !name.contains("curry") {
            return FoodUnit(label: "cup", gramsEquivalent: cupGrams(for: name))
        }

        // Soups, stews, broths, liquid desserts — served by bowl
        if name.contains("soup") || name.contains("stew") || name.contains("chowder") ||
           name.contains("bisque") || name.contains("broth") || name.contains("rasam") ||
           name.contains("sambar") || name.contains("payasam") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }

        // Spice powders and blends — teaspoon (ss ≤ 15 distinguishes a spice from a dish)
        if ss <= 15 &&
           (name.contains("powder") || name.contains("garam masala") || name.contains("chaat masala") ||
            name.contains("turmeric") || name.contains("cumin") || name.contains("coriander powder") ||
            name.contains("paprika") || name.contains("cayenne") || name.contains("cardamom") ||
            name.contains("cinnamon") || name.contains("ginger powder") || name.contains("garlic powder") ||
            name.contains("onion powder") || name.contains("curry powder") || name.contains("seasoning") ||
            name.contains("oregano") || name.contains("thyme") || name.contains("rosemary") ||
            name.contains("chili powder") || name.contains("pepper powder") || name.contains("spice blend")) {
            return FoodUnit(label: "tsp", gramsEquivalent: 3)
        }

        // Indian curries, sabzis, biryanis — served by bowl (ss > 50 to avoid spice blends)
        // Exclude beverages like masala chai, masala tea
        if (name.contains("curry") || name.contains("sabzi") || name.contains("sabji") ||
            name.contains("saag") || name.contains("makhani") || name.contains("biryani") ||
            name.contains("pulao") || name.contains("pilaf") || name.contains("khichdi") ||
            name.contains("masala") || name.contains("kheer") || name.contains("halwa")) && ss > 50
           && !words.contains("chai") && !words.contains("tea") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }

        // Tikka — pieces of meat/paneer (not tikka masala curry, which the masala rule above catches)
        if name.contains("tikka") { return FoodUnit(label: "piece", gramsEquivalent: ss) }

        // Yogurt / curd — measured in cups
        if words.contains("yogurt") || words.contains("curd") || words.contains("dahi") ||
           name.contains("yoghurt") || name.contains("raita") {
            return FoodUnit(label: "cup", gramsEquivalent: cupGrams(for: name))
        }

        // Indian grain dishes — measured by cup
        if name.contains("upma") || (name.contains("poha") && !name.contains("chivda")) {
            return FoodUnit(label: "cup", gramsEquivalent: cupGrams(for: name))
        }

        // Oats, cereals — measured in cups (exclude bars, which are pieces)
        if (name.contains("oatmeal") || name.contains("oats") || name.contains("porridge") ||
            name.contains("granola") || name.contains("muesli") || name.contains("cereal") ||
            name.contains("corn flakes") || name.contains("cornflakes")) && !name.contains("bar") {
            return FoodUnit(label: "cup", gramsEquivalent: cupGrams(for: name))
        }

        // Pasta and noodles — measured in cups (cooked portions)
        if name.contains("pasta") || name.contains("spaghetti") || name.contains("penne") ||
           name.contains("macaroni") || name.contains("fettuccine") || name.contains("linguine") ||
           name.contains("fusilli") || name.contains("rigatoni") || name.contains("noodle") {
            return FoodUnit(label: "cup", gramsEquivalent: cupGrams(for: name))
        }

        // Smoothies and shakes — measured by cup
        if name.contains("smoothie") || name.contains("shake") {
            return FoodUnit(label: "cup", gramsEquivalent: cupGrams(for: name))
        }

        // Chai and tea — cup (natural serving for hot beverages, before ml catch-all)
        if words.contains("chai") || words.contains("tea") {
            return FoodUnit(label: "cup", gramsEquivalent: 240)
        }

        // Sprouts — piece for Brussels, cup for bean/lentil/mung sprouts
        if name.contains("brussels sprout") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        if name.contains("sprout") || name.contains("sprouted") {
            return FoodUnit(label: "cup", gramsEquivalent: 90)
        }

        // Liquid items (word boundaries to avoid "steak"→"tea", "classic"→"lassi")
        if words.contains("milk") || words.contains("juice") || words.contains("lassi") ||
           words.contains("coffee") ||
           name.contains("buttermilk") ||
           // Alcoholic and other beverages
           words.contains("wine") || words.contains("beer") || words.contains("lager") ||
           words.contains("ale") || words.contains("cider") ||
           name.contains("kombucha") || name.contains("coconut water") ||
           name.contains("sparkling water") || name.contains("tonic water") ||
           name.contains("club soda") || name.contains("energy drink") ||
           name.contains("sports drink") || name.contains("lemonade") ||
           name.contains("limeade") || name.contains("soda water") ||
           name.contains("cola") || name.contains("gatorade") || name.contains("powerade") {
            return FoodUnit(label: "ml", gramsEquivalent: 1)
        }

        // Sandwiches, burgers, tacos, and similar handheld foods — piece
        if name.contains("burger") || name.contains("taco") || name.contains("burrito") ||
           name.contains("hot dog") || name.contains("hotdog") || name.contains("frank") ||
           name.contains("sandwich") || name.contains("kebab") || name.contains("shawarma") ||
           name.contains("falafel") || name.contains("crepe") || name.contains("sushi") ||
           name.contains("maki") || name.contains("dumpling") && !name.contains("soup") ||
           words.contains("roll") && !name.contains("spring roll") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        // Spring rolls are also piece — catch after the words.contains("roll") exclusion above
        if name.contains("spring roll") || name.contains("egg roll") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Large fruits — by piece
        if (name.contains("mango") && !name.contains("chutney") && !name.contains("lassi") && !name.contains("juice")) ||
           (name.contains("papaya") && !name.contains("juice")) ||
           (name.contains("watermelon") && !name.contains("juice")) ||
           (name.contains("pineapple") && !name.contains("juice")) ||
           name.contains("jackfruit") || name.contains("litchi") || name.contains("lychee") ||
           (name.contains("pomegranate") && !name.contains("juice")) {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Small fruits and berries — by cup
        if name.contains("strawberr") || name.contains("blueberr") ||
           name.contains("raspberr") || name.contains("blackberr") ||
           name.contains("grapes") || (name.contains("cherr") && !name.contains("tomato")) {
            return FoodUnit(label: "cup", gramsEquivalent: 150)
        }

        // Whole vegetables — by piece
        if name.contains("sweet potato") ||
           (name.contains("carrot") && !name.contains("cake") && !name.contains("juice")) ||
           (name.contains("cucumber") && !name.contains("pickle")) ||
           (name.contains("avocado") && !name.contains("ranch") && !name.contains("toast")) ||
           name.contains("capsicum") || name.contains("bell pepper") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        return FoodUnit(label: "serving", gramsEquivalent: ss)
    }

    private static func pieceGrams(for name: String) -> Double {
        if name.contains("capsicum") || name.contains("bell pepper") { return 150 }
        if name.contains("onion") { return 110 }
        if name.contains("tomato") { return 120 }
        if name.contains("potato") { return 150 }
        if name.contains("carrot") { return 70 }
        if name.contains("cucumber") { return 200 }
        if name.contains("zucchini") { return 200 }
        if name.contains("eggplant") || name.contains("brinjal") { return 300 }
        if name.contains("avocado") { return 150 }
        if name.contains("lemon") || name.contains("lime") { return 60 }
        if name.contains("mango") { return 200 }
        if name.contains("peach") || name.contains("pear") { return 170 }
        if name.contains("plum") || name.contains("apricot") { return 65 }
        if name.contains("guava") { return 100 }
        if name.contains("kiwi") { return 75 }
        if name.contains("fig") { return 50 }
        if name.contains("corn") { return 90 } // one ear
        if name.contains("beet") { return 80 }
        if name.contains("radish") { return 15 }
        if name.contains("turnip") { return 120 }
        return 100 // default piece weight
    }

    private static func cupGrams(for name: String) -> Double {
        if name.contains("rice") { return 185 }
        if name.contains("quinoa") { return 185 }
        if name.contains("oats") || name.contains("oatmeal") { return 80 }
        if name.contains("granola") { return 120 }
        if name.contains("muesli") { return 85 }
        if name.contains("flour") || name.contains("atta") { return 120 }
        if name.contains("pasta") || name.contains("spaghetti") || name.contains("penne") ||
           name.contains("macaroni") || name.contains("noodle") { return 140 }  // cooked
        if name.contains("dal") || name.contains("lentil") { return 200 }
        if name.contains("chickpea") || name.contains("chole") || name.contains("rajma") { return 164 }
        if name.contains("black bean") || name.contains("kidney bean") ||
           name.contains("pinto bean") || name.contains("navy bean") { return 172 }  // cooked
        if name.contains("paneer") { return 150 }
        if name.contains("yogurt") || name.contains("curd") || name.contains("dahi") { return 245 }
        if name.contains("poha") { return 60 }
        return 240
    }
}
