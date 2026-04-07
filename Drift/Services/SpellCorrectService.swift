import Foundation

/// Spell correction using food DB names + hardcoded fallback.
/// Corrects user input before passing to LLM or food search.
enum SpellCorrectService {

    /// Cached food names from DB for fuzzy matching
    nonisolated(unsafe) private static var foodNames: [String] = {
        // Load food names from the bundled DB at startup
        guard let url = Bundle.main.url(forResource: "foods", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let foods = try? JSONDecoder().decode([[String: AnyCodable]].self, from: data) else {
            return []
        }
        return foods.compactMap { $0["name"]?.value as? String }.map { $0.lowercased() }
    }()

    /// Curated corrections (edit distance can't catch these well)
    private static let hardcoded: [String: String] = [
        "chiken": "chicken", "chickin": "chicken", "chikken": "chicken",
        "bananaa": "banana", "bananna": "banana",
        "brocoli": "broccoli", "brocolli": "broccoli",
        "avacado": "avocado", "avocadao": "avocado",
        "protien": "protein", "proteen": "protein", "protine": "protein",
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
        "piza": "pizza", "pizzza": "pizza",
        "coffe": "coffee", "cofee": "coffee",
        "excercise": "exercise", "exercize": "exercise",
        "benchpress": "bench press",
        "deadlfit": "deadlift", "dedlift": "deadlift",
        "wieght": "weight", "weigth": "weight",
        "calries": "calories", "calroies": "calories",
    ]

    /// Correct spelling. Checks hardcoded first, then fuzzy-matches against food DB.
    static func correct(_ text: String) -> String {
        let words = text.components(separatedBy: " ")
        var result: [String] = []
        var changed = false

        for word in words {
            let lower = word.lowercased()

            // Hardcoded corrections first
            if let fix = hardcoded[lower] {
                result.append(fix)
                changed = true
                continue
            }

            // Skip short words and common English words
            if lower.count < 4 || commonWords.contains(lower) {
                result.append(word)
                continue
            }

            // Fuzzy match against food DB names (edit distance ≤ 2)
            if let match = closestFoodWord(lower) {
                result.append(match)
                changed = true
            } else {
                result.append(word)
            }
        }

        return changed ? result.joined(separator: " ") : text
    }

    /// Find the closest food name word within edit distance 2.
    private static func closestFoodWord(_ word: String) -> String? {
        // Check against individual words from food names
        var best: (word: String, distance: Int)?
        for name in foodNames {
            let nameWords = name.split(separator: " ").map { String($0).filter(\.isLetter) }
            for nameWord in nameWords {
                guard nameWord.count >= 4 else { continue }
                let dist = editDistance(word, nameWord)
                if dist == 1 && dist < (best?.distance ?? Int.max) {
                    best = (nameWord, dist)
                }
            }
        }
        return best?.word
    }

    /// Levenshtein edit distance between two strings.
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        var dp = Array(0...n)
        for i in 1...m {
            var prev = dp[0]
            dp[0] = i
            for j in 1...n {
                let temp = dp[j]
                dp[j] = a[i-1] == b[j-1] ? prev : min(prev, dp[j], dp[j-1]) + 1
                prev = temp
            }
        }
        return dp[n]
    }

    /// Common English words to skip (not food/exercise terms)
    private static let commonWords: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "have", "had",
        "just", "some", "about", "what", "when", "how", "much", "many",
        "today", "yesterday", "calories", "protein", "carbs", "should",
        "log", "ate", "had", "add", "track", "eating", "drank", "made",
    ]
}

/// Helper for JSON decoding with any type
private struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { value = s }
        else if let d = try? container.decode(Double.self) { value = d }
        else if let b = try? container.decode(Bool.self) { value = b }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let s = value as? String { try container.encode(s) }
        else if let d = value as? Double { try container.encode(d) }
    }
}
