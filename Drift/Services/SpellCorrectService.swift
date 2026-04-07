import Foundation

/// Spell correction for user input before passing to LLM or food search.
/// Uses a curated dictionary of common food/fitness misspellings.
enum SpellCorrectService {

    /// Common misspellings → corrections (food + fitness terms)
    private static let corrections: [String: String] = [
        // Food
        "chiken": "chicken", "chickin": "chicken", "chikken": "chicken",
        "bananaa": "banana", "bananna": "banana",
        "brocoli": "broccoli", "brocolli": "broccoli",
        "avacado": "avocado", "avocadao": "avocado",
        "protien": "protein", "proteen": "protein",
        "calries": "calories", "calroies": "calories", "caloris": "calories",
        "breakfest": "breakfast", "brekfast": "breakfast",
        "sandwhich": "sandwich", "sandwitch": "sandwich",
        "spagetti": "spaghetti", "spagehtti": "spaghetti",
        "tomatoe": "tomato", "potatoe": "potato",
        "yoghurt": "yogurt", "yougurt": "yogurt",
        "oatmeel": "oatmeal", "oatemeal": "oatmeal",
        "panner": "paneer", "panneer": "paneer",
        "samossa": "samosa", "somosa": "samosa",
        "chappati": "chapati", "chappathi": "chapati",
        "biryanni": "biryani", "biriyani": "biryani",
        "daal": "dal", "dhal": "dal",
        "rotii": "roti", "rottie": "roti",
        "naan": "naan", // already correct but common search
        "saald": "salad", "sallad": "salad",
        "almonds": "almonds", // correct
        "piza": "pizza", "pizzza": "pizza",
        "coffe": "coffee", "cofee": "coffee",
        // Fitness
        "excercise": "exercise", "exercize": "exercise",
        "squatt": "squat", "squats": "squats",
        "benchpress": "bench press",
        "deadlfit": "deadlift", "dedlift": "deadlift",
        "workoout": "workout", "workot": "workout",
        "calroie": "calorie", "calorie": "calorie",
        "wieght": "weight", "weigth": "weight",
        "protine": "protein",
    ]

    /// Correct spelling in text. Returns original if no corrections found.
    static func correct(_ text: String) -> String {
        let words = text.components(separatedBy: " ")
        var result: [String] = []
        var changed = false

        for word in words {
            let lower = word.lowercased()
            if let fix = corrections[lower] {
                // Preserve original capitalization pattern
                if word.first?.isUppercase == true {
                    result.append(fix.prefix(1).uppercased() + fix.dropFirst())
                } else {
                    result.append(fix)
                }
                changed = true
            } else {
                result.append(word)
            }
        }

        return changed ? result.joined(separator: " ") : text
    }
}
