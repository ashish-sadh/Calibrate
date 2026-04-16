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
        // Boiled/fried/poached egg entries often have ss=100 in DB but are clearly single eggs
        if words.contains("egg") && !name.contains("egg roll") && !name.contains("egg noodle") &&
           !name.contains("fried rice") && !name.contains("benedict") &&
           (ss <= 110 || name.contains("boiled egg") || name.contains("fried egg") ||
            name.contains("poached egg") || name.contains("egg white") || name.contains("whole") ||
            name.contains("organic") || name.contains("large egg") || name.contains("grade a")) {
            return FoodUnit(label: "egg", gramsEquivalent: ss)
        }
        if name.contains("meatball") { return FoodUnit(label: "meatball", gramsEquivalent: ss) }

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

        // Chaat and Indian snack mixes — served by bowl (must precede puri/poori flatbread check)
        if name.contains("bhel") || name.contains("sev puri") || name.contains("papdi chaat") ||
           name.contains("dahi puri") || name.contains("pani puri") ||
           (name.contains("chaat") && !name.contains("chaat masala")) {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }

        // Additional Indian flatbreads
        if name.contains("puri") || name.contains("poori") || name.contains("bhatura") ||
           name.contains("bhatoora") || name.contains("thepla") || name.contains("phulka") ||
           name.contains("appam") || name.contains("pesarattu") || name.contains("adai") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Indian flatbread — bhakri (Maharashtrian, distinct from roti)
        if name.contains("bhakri") { return FoodUnit(label: "piece", gramsEquivalent: ss) }

        // More Indian flatbreads and stuffed breads
        if name.contains("luchi") || name.contains("puran poli") || name.contains("thalipeeth") ||
           name.contains("kori rotti") || name.contains("siddu") || name.contains("manakeesh") ||
           name.contains("manakish") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Indian sweets — always countable by piece
        if name.contains("gulab") || name.contains("jamun") || name.contains("laddu") ||
           name.contains("laddoo") || name.contains("ladoo") || name.contains("barfi") ||
           name.contains("burfi") || name.contains("jalebi") || name.contains("rasgulla") ||
           name.contains("rasmalai") || name.contains("modak") || name.contains("peda") ||
           name.contains("gujiya") || name.contains("mithai") || name.contains("pinni") ||
           name.contains("kaju katli") || name.contains("kalakand") || name.contains("mysore pak") ||
           name.contains("sandesh") || name.contains("malpua") || name.contains("soan papdi") ||
           name.contains("bebinca") || name.contains("kozhukattai") || name.contains("thekua") ||
           name.contains("baklava") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Indian milk-based desserts — bowl (must precede generic soup/stew check)
        if name.contains("rabri") || name.contains("shrikhand") || name.contains("basundi") ||
           name.contains("phirni") || name.contains("seviyan") || name.contains("sevai") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }

        // Omelette / frittata — single-serve egg dish
        if name.contains("omelette") || name.contains("omelet") || name.contains("frittata") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Scrambled eggs, egg bhurji — cooked egg dishes (like omelette, single serve)
        if name.contains("scrambled") || name.contains("bhurji") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        // Eggs Benedict — plated egg dish, single serve
        if name.contains("benedict") || name.contains("shakshuka") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Indian snack pieces: dhokla, khakhra, chilla, fafda, handvo
        if name.contains("dhokla") || name.contains("khaman") || name.contains("fafda") ||
           name.contains("handvo") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        if name.contains("khakhra") { return FoodUnit(label: "piece", gramsEquivalent: ss) }
        if name.contains("chilla") || name.contains("cheela") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Indian snack pieces and stuffed bites
        if name.contains("khandvi") || name.contains("paniyaram") || name.contains("kuzhi") ||
           name.contains("dabeli") || name.contains("pakoda") || name.contains("gur papdi") ||
           name.contains("litti") || name.contains("puttu") || name.contains("ribbon pakoda") ||
           name.contains("pitha") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Pav bhaji (dish) — bowl; standalone pav (bread roll) — piece
        if name.contains("pav bhaji") || name.contains("misal") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }
        if words.contains("pav") { return FoodUnit(label: "piece", gramsEquivalent: ss) }

        // French toast, croissant, danish → piece (must precede bread/toast → slice rule)
        if name.contains("french toast") || name.contains("croissant") || name.contains("danish") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Bagel, baguette, kulcha — piece (don't contain "bread", so bread rule won't catch them)
        if name.contains("bagel") || name.contains("baguette") || name.contains("kulcha") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Focaccia — served by slice (Italian flatbread)
        if name.contains("focaccia") { return FoodUnit(label: "slice", gramsEquivalent: ss) }

        // Sliceable foods ("Bread Pudding" excluded — it's a dessert bowl, not sliceable bread)
        if (name.contains("bread") || name.contains("toast")) &&
           !name.contains("breadfruit") && !name.contains("breadstick") &&
           !name.contains("pudding") {
            return FoodUnit(label: "slice", gramsEquivalent: ss)
        }
        if name.contains("pizza") { return FoodUnit(label: "slice", gramsEquivalent: ss) }
        if name.contains("date") && !name.contains("update") { return FoodUnit(label: "piece", gramsEquivalent: ss) }
        if name.contains("tortilla") || name.contains("wrap") { return FoodUnit(label: "piece", gramsEquivalent: ss) }
        if name.contains("wing") || name.contains("nugget") || name.contains("tender") { return FoodUnit(label: "piece", gramsEquivalent: ss) }
        // Meat cuts and portions — single-serve pieces
        if name.contains("chicken breast") || name.contains("chicken thigh") ||
           name.contains("chicken leg") || name.contains("pork chop") ||
           name.contains("lamb chop") || name.contains("chicken lollipop") ||
           name.contains("chicken cutlet") || name.contains("chicken drumstick") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        // Beef and pork whole-cut steaks — single piece (including filet mignon which lacks "steak")
        if name.contains("steak") && !name.contains("sauce") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        if name.contains("filet mignon") || name.contains("duck breast") || name.contains("duck leg") ||
           name.contains("roasted duck") || name.contains("peking duck") || name.contains("venison") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Tandoori items — piece (grilled on skewer or served as individual portion)
        if name.contains("tandoori") { return FoodUnit(label: "piece", gramsEquivalent: ss) }

        // Fried/grilled bites and skewers
        if name.contains("chicken 65") || name.contains("fish 65") || name.contains("shrimp 65") ||
           name.contains("karaage") || name.contains("katsu") || name.contains("skewer") ||
           name.contains("satay") || name.contains("yakitori") || name.contains("malai boti") ||
           name.contains("chicken piccata") || name.contains("pot pie") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        if name.contains("waffle") || name.contains("pancake") || name.contains("donut") || name.contains("doughnut") { return FoodUnit(label: "piece", gramsEquivalent: ss) }
        if name.contains("brownie") || name.contains("muffin") || name.contains("cupcake") { return FoodUnit(label: "piece", gramsEquivalent: ss) }
        if name.contains("banana") && ss < 160 { return FoodUnit(label: "banana", gramsEquivalent: ss) }
        if name.contains("apple") && ss < 250 { return FoodUnit(label: "apple", gramsEquivalent: ss) }
        if name.contains("orange") && ss < 200 { return FoodUnit(label: "orange", gramsEquivalent: ss) }
        if name.contains("cookie") || name.contains("biscuit") { return FoodUnit(label: "piece", gramsEquivalent: ss) }
        if name.contains("scoop") { return FoodUnit(label: "scoop", gramsEquivalent: ss) }
        // Almond butter → tbsp (before almond rule which excludes "butter" forms)
        if name.contains("almond butter") { return FoodUnit(label: "tbsp", gramsEquivalent: 16) }
        // Peanut butter — tbsp (peanut excluded from generic butter word rule)
        if name.contains("peanut butter") || name.contains("pb2") {
            return FoodUnit(label: "tbsp", gramsEquivalent: 32)
        }

        // Nuts — show count as secondary unit (exclude bars which contain nut names e.g. "Built Bar (Coconut Almond)")
        if name.contains("almond") && !name.contains("milk") && !name.contains("butter") &&
           !name.contains("flour") && !name.contains("bar") {
            return FoodUnit(label: "serving", gramsEquivalent: ss)
        }
        if name.contains("cashew") && !name.contains("butter") && !name.contains("bar") {
            return FoodUnit(label: "serving", gramsEquivalent: ss)
        }
        if name.contains("pistachio") { return FoodUnit(label: "serving", gramsEquivalent: ss) }
        if name.contains("walnut") { return FoodUnit(label: "serving", gramsEquivalent: ss) }

        // Protein powder — measured by scoop
        if name.contains("protein powder") {
            return FoodUnit(label: "scoop", gramsEquivalent: ss)
        }
        // Whey protein, protein isolate/concentrate → scoop
        if name.contains("whey protein") || name.contains("protein isolate") || name.contains("protein concentrate") {
            return FoodUnit(label: "scoop", gramsEquivalent: ss)
        }

        // Collagen and greens supplements — scoop
        if name.contains("collagen") || name.contains("ag1") || name.contains("athletic greens") ||
           name.contains("greens powder") {
            return FoodUnit(label: "scoop", gramsEquivalent: ss)
        }
        // Fibre and bran supplements — tablespoon
        if name.contains("psyllium") || name.contains("wheat bran") {
            return FoodUnit(label: "tbsp", gramsEquivalent: 10)
        }
        // Supplement gummies — piece (vitamins, collagen gummies)
        if name.contains("gummies") || name.contains("gummy") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        // Soya chunks (textured vegetable protein) — cup
        if name.contains("soya chunk") || name.contains("soy chunk") {
            return FoodUnit(label: "cup", gramsEquivalent: 50)
        }
        // Tempeh, seitan — piece (dense fermented/wheat block, single-serve portion)
        if name.contains("tempeh") || name.contains("seitan") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Parmesan and feta — grated/crumbled topping; measured by tbsp
        if name.contains("parmesan") || name.contains("feta") {
            return FoodUnit(label: "tbsp", gramsEquivalent: 15)
        }

        // String cheese — individual stick
        if name.contains("string cheese") { return FoodUnit(label: "piece", gramsEquivalent: ss) }
        // Mozzarella sticks (fried) — piece (before mozzarella slice rule below)
        if name.contains("mozzarella stick") { return FoodUnit(label: "piece", gramsEquivalent: ss) }
        // Burrata — single ball
        if name.contains("burrata") { return FoodUnit(label: "piece", gramsEquivalent: ss) }

        // Hard block cheeses — slice (1 oz ≈ 28g per slice)
        if (name.contains("cheddar") || name.contains("mozzarella") || name.contains("provolone") ||
            name.contains("gruyere") || name.contains("gouda") || name.contains("halloumi") ||
            name.contains("colby") || name.contains("monterey jack") || name.contains("pepper jack") ||
            name.contains("swiss cheese") || name.contains("saganaki")) &&
           !name.contains("shredded") && !name.contains("grated") {
            return FoodUnit(label: "slice", gramsEquivalent: 28)
        }

        // Soft/spreadable cheeses — tablespoon
        if name.contains("brie") || name.contains("goat cheese") || name.contains("mascarpone") ||
           name.contains("ricotta") || name.contains("quark") || name.contains("labneh") ||
           (name.contains("blue cheese") && !name.contains("dressing")) {
            return FoodUnit(label: "tbsp", gramsEquivalent: 14)
        }

        // Shredded or grated cheese — measured by cup
        if name.contains("shredded") || name.contains("grated") {
            return FoodUnit(label: "cup", gramsEquivalent: 112)
        }

        // Condiments and dips — tablespoon (before oil/ghee to avoid double-matching)
        if name.contains("ketchup") || name.contains("salsa") || name.contains("guacamole") ||
           name.contains("hummus") || name.contains("tahini") || name.contains("sriracha") ||
           name.contains("hot sauce") || name.contains("soy sauce") || name.contains("bbq sauce") ||
           name.contains("fish sauce") || name.contains("oyster sauce") || name.contains("hoisin") ||
           name.contains("teriyaki sauce") || name.contains("vinaigrette") || name.contains("relish") ||
           name.contains("aioli") || name.contains("mayo") || name.contains("mayonnaise") ||
           name.contains("ranch") || name.contains("pesto") || name.contains("chili sauce") ||
           name.contains("chutney") || name.contains("tamarind sauce") || name.contains("tzatziki") ||
           name.contains("baba ganoush") || name.contains("baba ghanoush") ||
           name.contains("miso paste") || name.contains("coconut aminos") ||
           name.contains("alfredo sauce") || name.contains("marinara sauce") ||
           name.contains("enchilada sauce") || name.contains("chimichurri") ||
           name.contains("queso dip") || name.contains("pico de gallo") ||
           name.contains("balsamic vinegar") || name.contains("yellow mustard") ||
           name.contains("labneh") || name.contains("harissa") {
            return FoodUnit(label: "tbsp", gramsEquivalent: 15)
        }

        // Tablespoon items (word boundaries: "boiled" contains "oil", "butternut" contains "butter")
        if words.contains("oil") || words.contains("ghee") { return FoodUnit(label: "tbsp", gramsEquivalent: 15) }
        if words.contains("butter") && !name.contains("peanut") && !name.contains("almond") && !name.contains("paneer") {
            return FoodUnit(label: "tbsp", gramsEquivalent: 14)
        }

        // Honey, jam, jelly, marmalade — tablespoon
        // Use word boundary for "honey" to avoid "honeydew" matching
        if words.contains("honey") ||
           (name.contains("jam") && !name.contains("jamun")) ||
           (name.contains("jelly") && !name.contains("jellyfish")) ||
           name.contains("marmalade") ||
           (name.contains("syrup") && !name.contains("cough")) ||
           name.contains("agave") {
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

        // Indian crispy snack pieces (individual pieces, not loose mix)
        if name.contains("chakli") || name.contains("murukku") || name.contains("mathri") ||
           name.contains("bhakarwadi") || name.contains("namak pare") || name.contains("shakarpara") ||
           name.contains("shakkar pare") || name.contains("seedai") || name.contains("chikki") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        // Loose Indian snack mixes — by cup
        if name.contains("murmura") ||
           (name.contains("sev") && !name.contains("puri")) ||
           name.contains("chivda") || name.contains("namkeen") {
            return FoodUnit(label: "cup", gramsEquivalent: 30)
        }

        // Bars — measured by piece (protein bar, granola bar, energy bar, cereal bar, Built Bar, etc.)
        if name.contains("protein bar") || name.contains("granola bar") ||
           name.contains("energy bar") || name.contains("cereal bar") ||
           name.contains("snack bar") || name.contains("built bar") ||
           name.contains("cliff bar") || name.contains("kind bar") ||
           name.contains("rxbar") || name.contains("larabar") ||
           name.contains("quest bar") || name.contains("one bar") ||
           (name.contains("bar") && name.contains("nut")) {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Crackers and crispy snacks — piece
        if name.contains("rice cake") || name.contains("graham cracker") ||
           name.contains("cheez-it") || name.contains("goldfish cracker") ||
           name.contains("pita chip") || name.contains("corn chip") ||
           name.contains("protein chip") || name.contains("pretzel") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Nachos and loaded fries — bowl
        if name.contains("nacho") || name.contains("poutine") || name.contains("loaded fries") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }

        // Hash browns — piece (potato patty)
        if name.contains("hash brown") { return FoodUnit(label: "piece", gramsEquivalent: ss) }

        // Coleslaw — bowl (side salad)
        if name.contains("coleslaw") || name.contains("cole slaw") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
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

        // Polenta, grits, risotto — measured in cups (porridge/grain consistency)
        if name.contains("polenta") || name.contains("grits") || name.contains("risotto") {
            return FoodUnit(label: "cup", gramsEquivalent: cupGrams(for: name))
        }

        // Ancient/whole grains — measured in cups (cooked)
        if name.contains("barley") || name.contains("bulgur") || name.contains("farro") ||
           name.contains("freekeh") || name.contains("millet") || name.contains("sorghum") ||
           name.contains("teff") || name.contains("amaranth") {
            return FoodUnit(label: "cup", gramsEquivalent: 182)
        }

        // Flours and meals — measured in cups (baking dry ingredient)
        if name.contains("besan") || name.contains("bajra") || name.contains("maida") ||
           name.contains("ragi") || name.contains("jowar") ||
           (words.contains("flour") && !name.contains("bread")) {
            return FoodUnit(label: "cup", gramsEquivalent: 120)
        }

        // Popcorn — cup (air-popped ≈ 8g/cup; must precede corn rule)
        if name.contains("popcorn") { return FoodUnit(label: "cup", gramsEquivalent: 8) }
        // Corn on the cob — piece; elote (Mexican street corn) — piece
        if name.contains("corn on the cob") || name.contains("elote") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        // Loose corn kernels (canned, cooked, frozen) — cup
        if name.contains("corn") && !name.contains("chip") && !name.contains("dog") &&
           !name.contains("flake") && !name.contains("cornflake") {
            return FoodUnit(label: "cup", gramsEquivalent: 154)
        }

        // Pho (Vietnamese noodle soup) and ramen — bowl (don't contain "soup")
        if name.contains("pho") || name.contains("ramen") || name.contains("ramyeon") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }

        // Named soups and stews that don't contain "soup" or "stew"
        if name.contains("minestrone") || name.contains("tom kha") || name.contains("tom yum") ||
           name.contains("pozole") || name.contains("kimchi jjigae") || name.contains("sundubu") ||
           name.contains("mulligatawny") || name.contains("laksa") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }

        // Soups, stews, broths, liquid desserts, chili (dish) — served by bowl
        // ss > 15 guard keeps spice powders (chili powder, chili flakes) from matching
        if name.contains("soup") || name.contains("stew") || name.contains("chowder") ||
           name.contains("bisque") || name.contains("broth") || name.contains("rasam") ||
           name.contains("sambar") || name.contains("payasam") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }
        if (words.contains("chili") || words.contains("chilli")) && ss > 15 &&
           !name.contains("chili powder") && !name.contains("chili sauce") && !name.contains("chili oil") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }

        // Pudding, custard, mousse — bowl (ss > 50 excludes tiny spice-quantity items)
        if ss > 50 && (name.contains("pudding") || name.contains("custard") || name.contains("mousse")) {
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

        // Bhujia (loose crispy snack, e.g. Haldiram's Aloo Bhujia) — cup
        if name.contains("bhujia") { return FoodUnit(label: "cup", gramsEquivalent: 30) }
        // Aloo (potato) Indian sabzis — bowl; aloo tikki (patty) → piece handled by tikki rule below
        if name.contains("aloo") && !name.contains("tikki") && !name.contains("bhujia") &&
           !name.contains("puri") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }
        // Keema (minced meat), haleem, nihari — slow-cooked/minced meat dishes
        if name.contains("keema") || name.contains("haleem") || name.contains("nihari") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }

        // Additional Indian bowl dishes
        if name.contains("pongal") || name.contains("usal") || name.contains("undhiyu") ||
           name.contains("sundal") || name.contains("mishti doi") || name.contains("ragda") ||
           name.contains("kottu") || name.contains("manchurian") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }
        if (name.contains("kadhai") || name.contains("kadai") || name.contains("kadhi")) &&
           !words.contains("chai") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }
        // Thali and South Indian Meals — bowl (full plate meal)
        if name.contains("thali") || name.contains("south indian meals") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }
        // South Indian and regional Indian dishes — bowl
        if name.contains("avial") || name.contains("aviyal") || name.contains("thoran") ||
           name.contains("poriyal") || name.contains("kootu") || name.contains("olan") ||
           name.contains("bisi bele") || name.contains("bisibele") || name.contains("bhutte") ||
           name.contains("zunka") || name.contains("pithla") || name.contains("dham") ||
           name.contains("galho") || name.contains("jadoh") || name.contains("kosha") ||
           name.contains("laal maas") || name.contains("ker sangri") || name.contains("eromba") ||
           name.contains("rugra") || name.contains("masor tenga") || name.contains("shorshe") ||
           name.contains("gongura") || name.contains("meen kuzhambu") || name.contains("karimeen") ||
           name.contains("doi maach") || name.contains("hilsa") || name.contains("rohu fish") ||
           name.contains("katla fish") || name.contains("fish molee") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }
        // Stir-fry dishes (by name, not by ingredient), rendang — bowl
        if (name.contains("stir fry") || name.contains("stir-fry")) && !name.contains("vegetable blend") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }
        if name.contains("rendang") { return FoodUnit(label: "bowl", gramsEquivalent: ss) }
        // Fajitas, bulgogi, Korean BBQ, Filipino, African dishes — bowl
        if name.contains("fajita") || name.contains("bulgogi") || name.contains("jerk chicken") ||
           name.contains("peri peri") || name.contains("piri piri") || name.contains("tocino") ||
           name.contains("arroz con pollo") || name.contains("bunny chow") ||
           name.contains("bobotie") || name.contains("kitfo") || name.contains("tibs") ||
           name.contains("doro wat") || name.contains("doro wot") || name.contains("shiro wat") ||
           name.contains("suya") ||
           name.contains("galbi") || name.contains("samgyeopsal") || name.contains("dakgui") ||
           name.contains("chettinad") || name.contains("chicken handi") || name.contains("chicken adobo") ||
           name.contains("korean bbq") || name.contains("korean fried chicken") ||
           name.contains("pork adobo") || name.contains("lechon") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }

        // Middle Eastern salads, meze, and similar dishes — bowl
        if name.contains("tabbouleh") || name.contains("tabouleh") || name.contains("fattoush") ||
           name.contains("ceviche") || name.contains("musakhan") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }

        // Chilaquiles and quesadilla — piece/bowl
        if name.contains("chilaquiles") { return FoodUnit(label: "bowl", gramsEquivalent: ss) }
        if name.contains("quesadilla") || name.contains("enchilada") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Indian curries, sabzis, biryanis — served by bowl (ss > 50 to avoid spice blends)
        // Exclude beverages like masala chai, masala tea
        if (name.contains("curry") || name.contains("sabzi") || name.contains("sabji") ||
            name.contains("saag") || name.contains("palak") || name.contains("makhani") ||
            name.contains("biryani") || name.contains("pulao") || name.contains("pilaf") ||
            name.contains("khichdi") || name.contains("masala") || name.contains("kheer") ||
            name.contains("halwa") || name.contains("bharta") ||
            name.contains("kofta") || name.contains("korma")) && ss > 50
           && !words.contains("chai") && !words.contains("tea") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }

        // Tikka/tikki — pieces of meat/paneer or potato patties
        if name.contains("tikka") || name.contains("tikki") { return FoodUnit(label: "piece", gramsEquivalent: ss) }

        // Bacon → strip (turkey bacon, Canadian bacon, crispy bacon)
        if name.contains("bacon") { return FoodUnit(label: "strip", gramsEquivalent: ss) }
        // Jerky → strip (beef, turkey, salmon jerky)
        if name.contains("jerky") { return FoodUnit(label: "strip", gramsEquivalent: ss) }
        // Sausage → link (turkey, chicken, pork, Italian — not sausage roll which is a pastry)
        if name.contains("sausage") && !name.contains("roll") { return FoodUnit(label: "link", gramsEquivalent: ss) }
        // Turkey → piece (roasted, sliced; ss > 50 excludes spice-quantity amounts)
        if words.contains("turkey") && ss > 50 { return FoodUnit(label: "piece", gramsEquivalent: ss) }

        // Deli meats and cured meats — slice
        if words.contains("ham") || name.contains("pepperoni") || name.contains("prosciutto") ||
           name.contains("salami") || name.contains("gyro meat") {
            return FoodUnit(label: "slice", gramsEquivalent: ss)
        }

        // Tofu — measured by cup (cubed portions in stir-fry, bowls)
        if name.contains("tofu") { return FoodUnit(label: "cup", gramsEquivalent: 126) }

        // Paneer standalone → cup (curry/masala dishes already exited above via curry rule)
        if name.contains("paneer") { return FoodUnit(label: "cup", gramsEquivalent: 150) }

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
           name.contains("fusilli") || name.contains("rigatoni") || name.contains("noodle") ||
           name.contains("mac and cheese") || name.contains("mac & cheese") ||
           name.contains("carbonara") || name.contains("cacio e pepe") || name.contains("gnocchi") {
            return FoodUnit(label: "cup", gramsEquivalent: cupGrams(for: name))
        }

        // Smoothies and shakes — measured by cup
        if name.contains("smoothie") || name.contains("shake") {
            return FoodUnit(label: "cup", gramsEquivalent: cupGrams(for: name))
        }

        // Mashed potatoes → cup (before generic potato → piece rule below)
        if name.contains("mashed potato") { return FoodUnit(label: "cup", gramsEquivalent: 210) }
        // Cottage cheese → cup
        if name.contains("cottage cheese") { return FoodUnit(label: "cup", gramsEquivalent: 226) }
        // Couscous → cup (cooked grain)
        if name.contains("couscous") { return FoodUnit(label: "cup", gramsEquivalent: 157) }

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

        // Branded soft drinks, energy drinks, and fermented dairy — ml
        if name.contains("pepsi") || name.contains("sprite") || name.contains("coke") ||
           name.contains("red bull") || name.contains("monster energy") || name.contains("fairlife") ||
           name.contains("kefir") || name.contains("diet coke") || name.contains("diet pepsi") {
            return FoodUnit(label: "ml", gramsEquivalent: 1)
        }

        // Liquid items (word boundaries to avoid "steak"→"tea", "classic"→"lassi")
        if words.contains("milk") || words.contains("juice") || words.contains("lassi") ||
           words.contains("coffee") ||
           name.contains("buttermilk") ||
           // Coffee shop drinks
           name.contains("latte") || name.contains("cappuccino") || name.contains("espresso") ||
           name.contains("macchiato") || name.contains("frappuccino") || name.contains("americano") ||
           name.contains("cold brew") || name.contains("matcha latte") ||
           // Indian and other drinks
           name.contains("aam panna") || name.contains("thandai") || name.contains("jaljeera") ||
           name.contains("nimbu pani") || name.contains("nimbu soda") || name.contains("shikanji") ||
           name.contains("rooh afza") || name.contains("kokum sharbat") ||
           name.contains("sattu drink") || name.contains("falooda") || name.contains("kahwa") ||
           name.contains("horchata") || name.contains("halo-halo") ||
           // Supplement drinks
           name.contains("bcaa drink") || name.contains("pre-workout drink") ||
           name.contains("electrolyte drink") ||
           // Spirits (word boundaries prevent "ginger"→"gin", "rump"→"rum")
           words.contains("vodka") || words.contains("whiskey") || words.contains("bourbon") ||
           words.contains("rum") || words.contains("tequila") || words.contains("gin") ||
           name.contains("margarita") ||
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

        // Shrimp and prawns — piece (cooked, grilled, cocktail, tempura portions)
        if name.contains("shrimp") || (name.contains("prawn") && !name.contains("balchao")) {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        // Shellfish and seafood pieces
        if name.contains("scallop") || name.contains("lobster") || name.contains("oyster") ||
           name.contains("mussel") || name.contains("clam") || name.contains("crab cake") ||
           name.contains("anchovies") || name.contains("sardine") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        // Fried/grilled fish preparations — piece
        if name.contains("fish fry") || name.contains("fish 65") || name.contains("fish and chips") ||
           name.contains("pomfret") || name.contains("fish and chip") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Fish fillets and whole fish portions — single-serve piece
        // ss > 70 distinguishes a fillet from a tiny topping/garnish amount
        if (name.contains("salmon") || name.contains("tilapia") || name.contains("halibut") ||
            name.contains("sea bass") || name.contains("seabass") || name.contains("snapper") ||
            name.contains("mahi") || name.contains("swordfish") || name.contains("mackerel") ||
            name.contains("trout") || name.contains("fillet") ||
            words.contains("cod") || words.contains("haddock")) && ss > 70 &&
           !name.contains("salad") && !name.contains("roll") && !name.contains("burger") &&
           !name.contains("bite") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Fast food sandwiches by brand name (don't contain "burger" or "sandwich")
        if name.contains("big mac") || name.contains("mcdouble") || name.contains("mcchicken") ||
           name.contains("filet-o-fish") || name.contains("quarter pounder") ||
           name.contains("whopper") || name.contains("veg whopper") || name.contains("dave's single") ||
           name.contains("in-n-out") || name.contains("brioche bun") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        // Calamari / fried squid rings — piece
        if name.contains("calamari") || name.contains("squid ring") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
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

        // Asian stir-fry, noodle, and rice dishes — bowl
        if name.contains("pad thai") || name.contains("pad see ew") || name.contains("pad kra pao") ||
           name.contains("general tso") || name.contains("kung pao") || name.contains("sweet and sour") ||
           name.contains("sesame chicken") || name.contains("char siu") ||
           name.contains("lo mein") || name.contains("chow mein") ||
           name.contains("bibimbap") || name.contains("japchae") ||
           name.contains("jajangmyeon") || name.contains("jjajangmyeon") || name.contains("dakgalbi") ||
           name.contains("nasi goreng") || name.contains("nasi lemak") || name.contains("pancit") ||
           name.contains("kare-kare") || name.contains("sinigang") || name.contains("sisig") ||
           name.contains("tteokbokki") || name.contains("okonomiyaki") || name.contains("cao lau") ||
           name.contains("bun cha") || name.contains("bun bo") || name.contains("thukpa") ||
           name.contains("bibim naengmyeon") || name.contains("bun thit nuong") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }

        // Fried/baked finger foods — piece
        if name.contains("empanada") || name.contains("calzone") || name.contains("chimichanga") ||
           name.contains("tamale") || name.contains("arepa") || name.contains("pupusa") ||
           name.contains("arancini") || name.contains("bao bun") || name.contains("steamed bao") ||
           name.contains("tostada") || name.contains("corn dog") ||
           name.contains("gyoza") || name.contains("takoyaki") || name.contains("kibbeh") ||
           name.contains("dolma") || name.contains("stuffed grape") || name.contains("spanakopita") ||
           name.contains("bruschetta") || name.contains("onion ring") || name.contains("cannoli") ||
           name.contains("churros") || name.contains("lumpia") || name.contains("injera") ||
           name.contains("dim sum") || name.contains("har gow") || name.contains("siu mai") ||
           name.contains("coconut macaroon") || name.contains("kimbap") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // African staple sides — piece (moulded portions)
        if name.contains("fufu") || name.contains("ugali") || name.contains("pounded yam") ||
           name.contains("akara") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Fried plantains — piece
        if name.contains("plantain") { return FoodUnit(label: "piece", gramsEquivalent: ss) }

        // Casserole, loaf, and cake-style desserts — slice
        if name.contains("meatloaf") || name.contains("lasagna") || name.contains("moussaka") ||
           name.contains("cottage pie") || name.contains("shepherd") ||
           name.contains("cheesecake") || name.contains("tiramisu") || name.contains("key lime pie") ||
           name.contains("tres leches") || name.contains("pumpkin pie") || name.contains("peach cobbler") {
            return FoodUnit(label: "slice", gramsEquivalent: ss)
        }
        // Cup/bowl desserts
        if name.contains("panna cotta") || name.contains("funnel cake") || name.contains("bingsu") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Pulled/shredded slow-cooked meats — cup
        if name.contains("carnitas") || name.contains("barbacoa") || name.contains("pulled pork") ||
           name.contains("al pastor") {
            return FoodUnit(label: "cup", gramsEquivalent: 140)
        }

        // Brisket, ribs — large cut pieces
        if name.contains("brisket") || name.contains("ribs") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Bowl foods by name (poke bowl, acai bowl, grain bowl, burrito bowl)
        if name.contains("bowl") { return FoodUnit(label: "bowl", gramsEquivalent: ss) }

        // Salads — served by bowl (dressings already handled by condiments tbsp rule above)
        if name.contains("salad") && !name.contains("dressing") {
            return FoodUnit(label: "bowl", gramsEquivalent: ss)
        }

        // Potato (boiled, baked, jacket) → piece; mashed caught above, sweet/chips/fries excluded
        if name.contains("potato") && !name.contains("chip") && !name.contains("fries") &&
           !name.contains("mashed") && !name.contains("sweet") {
            return FoodUnit(label: "piece", gramsEquivalent: ss > 0 ? ss : 150)
        }

        // Large fruits — by piece
        if (name.contains("mango") && !name.contains("chutney") && !name.contains("lassi") && !name.contains("juice")) ||
           (name.contains("papaya") && !name.contains("juice")) ||
           (name.contains("watermelon") && !name.contains("juice")) ||
           (name.contains("pineapple") && !name.contains("juice")) ||
           name.contains("jackfruit") || name.contains("litchi") || name.contains("lychee") ||
           (name.contains("pomegranate") && !name.contains("juice")) ||
           name.contains("cantaloupe") || name.contains("honeydew") ||
           (name.contains("melon") && !name.contains("watermelon")) {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Medium fruits — by piece
        if (name.contains("guava") && !name.contains("juice") && !name.contains("paste")) ||
           (name.contains("peach") && !name.contains("juice")) ||
           (name.contains("plum") && !name.contains("sauce")) ||
           name.contains("grapefruit") ||
           (name.contains("kiwi") && !name.contains("juice")) ||
           name.contains("dragon fruit") || name.contains("passion fruit") ||
           name.contains("starfruit") || name.contains("star fruit") ||
           name.contains("amla") || name.contains("bael") || name.contains("karonda") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Cherry tomatoes — cup (before small berries)
        if name.contains("cherry tomato") { return FoodUnit(label: "cup", gramsEquivalent: 150) }

        // Small fruits and berries — by cup
        if name.contains("strawberr") || name.contains("blueberr") ||
           name.contains("raspberr") || name.contains("blackberr") ||
           name.contains("grapes") || (name.contains("cherr") && !name.contains("tomato")) {
            return FoodUnit(label: "cup", gramsEquivalent: 150)
        }

        // Portobello — single whole mushroom; other mushrooms by cup
        if name.contains("portobello") || name.contains("portabella") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }
        if name.contains("mushroom") { return FoodUnit(label: "cup", gramsEquivalent: 70) }

        // Leafy greens — by cup
        if name.contains("arugula") || name.contains("romaine") ||
           (name.contains("lettuce") && !name.contains("taco")) {
            return FoodUnit(label: "cup", gramsEquivalent: 30)
        }

        // Cooked/raw vegetable portions — measured by cup
        if name.contains("broccoli") || name.contains("cauliflower") || name.contains("asparagus") ||
           name.contains("green bean") || name.contains("edamame") ||
           name.contains("kale") || (name.contains("spinach") && !name.contains("artichoke") && !name.contains("dip")) ||
           name.contains("bok choy") || name.contains("artichoke heart") ||
           name.contains("butternut squash") || name.contains("acorn squash") ||
           (name.contains("beet") && !name.contains("beetroot juice")) ||
           name.contains("snap pea") || name.contains("green pea") || name.contains("peas") ||
           name.contains("swiss chard") || name.contains("moringa") || name.contains("okra") ||
           name.contains("sauerkraut") {
            return FoodUnit(label: "cup", gramsEquivalent: ss > 0 ? ss : 90)
        }

        // Bengali/Indian stuffed eggplant dishes — piece (before generic eggplant rule)
        if name.contains("begun bhaja") || name.contains("bharwa baingan") ||
           name.contains("bharli vangi") || name.contains("stuffed brinjal") ||
           name.contains("stuffed eggplant") || name.contains("begun") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Whole vegetables — by piece
        if name.contains("sweet potato") ||
           (name.contains("carrot") && !name.contains("cake") && !name.contains("juice")) ||
           (name.contains("cucumber") && !name.contains("pickle")) ||
           (name.contains("avocado") && !name.contains("ranch") && !name.contains("toast")) ||
           name.contains("capsicum") || name.contains("bell pepper") ||
           name.contains("celery") ||
           name.contains("zucchini") || name.contains("courgette") ||
           name.contains("eggplant") || name.contains("brinjal") {
            return FoodUnit(label: "piece", gramsEquivalent: ss)
        }

        // Za'atar and similar spice blends used as condiments — tablespoon
        if name.contains("za'atar") || name.contains("zaatar") {
            return FoodUnit(label: "tbsp", gramsEquivalent: 15)
        }

        // Fermented/pickled vegetables — cup (kimchi, sauerkraut already handled above)
        if name.contains("kimchi") { return FoodUnit(label: "cup", gramsEquivalent: 100) }

        // Refried beans — cup (creamy, spoonable)
        if name.contains("refried bean") { return FoodUnit(label: "cup", gramsEquivalent: 240) }

        // Roasted puffed snacks — cup (makhana, trail mix)
        if name.contains("makhana") { return FoodUnit(label: "cup", gramsEquivalent: 30) }
        if name.contains("trail mix") { return FoodUnit(label: "cup", gramsEquivalent: 40) }

        // Aromatics used in small quantities
        if words.contains("garlic") { return FoodUnit(label: "piece", gramsEquivalent: ss) }
        if words.contains("ginger") && !name.contains("ale") && !name.contains("beer") {
            return FoodUnit(label: "tbsp", gramsEquivalent: 15)
        }

        // Jaggery / gur (Indian unrefined sugar) — tablespoon
        if name.contains("jaggery") || words.contains("gur") {
            return FoodUnit(label: "tbsp", gramsEquivalent: 20)
        }

        // Canned/tinned fish — serving (variable portion from can)
        if name.contains("canned tuna") || name.contains("canned salmon") ||
           name.contains("kirkland") && name.contains("tuna") {
            return FoodUnit(label: "serving", gramsEquivalent: ss)
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
        if name.contains("risotto") { return 185 }
        if name.contains("polenta") || name.contains("grits") { return 240 }
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
