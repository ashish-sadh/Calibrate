import XCTest
@testable import DriftCore

/// Tier-0 gold set for food logging — deterministic, no LLM, no network, <5s.
/// Covers: parseFoodIntent, parseMultiFoodIntent, ToolRanker log_food routing,
/// false-positive prevention, Indian meals, gram amounts, vague quantities.
///
/// Run: cd DriftCore && swift test --filter FoodLoggingGoldSetTests
final class FoodLoggingGoldSetTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            if ToolRegistry.shared.allTools().isEmpty {
                ToolRegistration.registerAll()
            }
        }
    }

    // MARK: - parseFoodIntent: Core Verbs

    func testParseFoodIntent_ExplicitVerbs() {
        let cases: [(String, String)] = [
            ("log 2 eggs", "egg"),
            ("ate a banana", "banana"),
            ("had rice for lunch", "rice"),
            ("add chicken breast", "chicken"),
            ("track paneer tikka", "paneer"),
            ("logged oatmeal", "oatmeal"),
            ("eating yogurt", "yogurt"),
            ("drank a glass of milk", "milk"),
            ("drinking orange juice", "orange"),
            ("made a smoothie", "smoothie"),
        ]
        var correct = 0
        for (query, expectedKeyword) in cases {
            let normalized = InputNormalizer.normalize(query).lowercased()
            if let intent = AIActionExecutor.parseFoodIntent(normalized),
               intent.query.lowercased().contains(expectedKeyword) {
                correct += 1
            } else {
                print("MISS (explicit verb): '\(query)'")
            }
        }
        print("📊 parseFoodIntent explicit verbs: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 explicit-verb miss")
    }

    func testParseFoodIntent_NaturalPhrases() {
        let cases: [(String, String)] = [
            ("I had 2 eggs for breakfast", "egg"),
            ("I ate chicken breast for dinner", "chicken"),
            ("just had a banana", "banana"),
            ("just ate some rice", "rice"),
            ("I'm having oatmeal", "oatmeal"),
            ("snacked on almonds", "almond"),
            ("I drank coffee", "coffee"),
            ("just drank a protein shake", "protein"),
        ]
        var correct = 0
        for (query, expectedKeyword) in cases {
            let normalized = InputNormalizer.normalize(query).lowercased()
            if let intent = AIActionExecutor.parseFoodIntent(normalized),
               intent.query.lowercased().contains(expectedKeyword) {
                correct += 1
            } else {
                print("MISS (natural phrase): '\(query)'")
            }
        }
        print("📊 parseFoodIntent natural phrases: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 natural-phrase miss")
    }

    func testParseFoodIntent_ConversationalPrefixes() {
        let cases: [(String, String)] = [
            ("can you log rice", "rice"),
            ("could you add chicken", "chicken"),
            ("please log a banana", "banana"),
            ("i want to log eggs", "egg"),
            ("i'd like to add yogurt", "yogurt"),
            ("let me log oatmeal", "oatmeal"),
        ]
        var correct = 0
        for (query, expectedKeyword) in cases {
            let normalized = InputNormalizer.normalize(query).lowercased()
            if let intent = AIActionExecutor.parseFoodIntent(normalized),
               intent.query.lowercased().contains(expectedKeyword) {
                correct += 1
            } else {
                print("MISS (conversational prefix): '\(query)'")
            }
        }
        print("📊 parseFoodIntent conversational prefixes: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 conversational-prefix miss")
    }

    // MARK: - parseFoodIntent: Gram Amounts

    func testParseFoodIntent_GramAmounts() {
        let cases: [(String, String, Double)] = [
            ("log 200g chicken", "chicken", 200),
            ("had 150g paneer", "paneer", 150),
            ("ate 100 grams of rice", "rice", 100),
            ("log 250g yogurt", "yogurt", 250),
            ("had 80g oats", "oat", 80),
        ]
        var correct = 0
        for (query, expectedKeyword, expectedGrams) in cases {
            let normalized = InputNormalizer.normalize(query).lowercased()
            if let intent = AIActionExecutor.parseFoodIntent(normalized),
               intent.query.lowercased().contains(expectedKeyword),
               let grams = intent.gramAmount, abs(grams - expectedGrams) < 1 {
                correct += 1
            } else {
                let intent = AIActionExecutor.parseFoodIntent(InputNormalizer.normalize(query).lowercased())
                print("MISS (gram amount): '\(query)' → query=\(intent?.query ?? "nil") grams=\(intent?.gramAmount.map { String($0) } ?? "nil")")
            }
        }
        print("📊 parseFoodIntent gram amounts: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 gram-amount miss")
    }

    // MARK: - parseFoodIntent: Vague Quantities

    func testParseFoodIntent_VagueQuantities() {
        let vagueQueries = [
            "had some rice",
            "ate a couple of eggs",
            "had a lot of chicken",
            "just had a little bit of oatmeal",
            "ate a few rotis",
            "had a handful of almonds",
            "had a bowl of dal",
            "ate a piece of cake",
        ]
        var detected = 0
        for query in vagueQueries {
            let normalized = InputNormalizer.normalize(query).lowercased()
            if AIActionExecutor.parseFoodIntent(normalized) != nil { detected += 1 }
            else { print("MISS (vague quantity): '\(query)'") }
        }
        print("📊 parseFoodIntent vague quantities: \(detected)/\(vagueQueries.count)")
        XCTAssertGreaterThanOrEqual(detected, vagueQueries.count - 2, "At most 2 vague-quantity misses")
    }

    // MARK: - parseFoodIntent: Meal-Type Hints

    func testParseFoodIntent_MealTypeHints() {
        let cases: [(String, String, String)] = [
            ("log eggs for breakfast", "egg", "breakfast"),
            ("had chicken for lunch", "chicken", "lunch"),
            ("ate pizza for dinner", "pizza", "dinner"),
            ("had yogurt for snack", "yogurt", "snack"),
        ]
        var correct = 0
        for (query, expectedFood, expectedMeal) in cases {
            let normalized = InputNormalizer.normalize(query).lowercased()
            if let intent = AIActionExecutor.parseFoodIntent(normalized),
               intent.query.lowercased().contains(expectedFood),
               intent.mealHint == expectedMeal {
                correct += 1
            } else {
                let i = AIActionExecutor.parseFoodIntent(InputNormalizer.normalize(query).lowercased())
                print("MISS (meal hint): '\(query)' → food=\(i?.query ?? "nil") meal=\(i?.mealHint ?? "nil")")
            }
        }
        print("📊 parseFoodIntent meal hints: \(correct)/\(cases.count)")
        XCTAssertEqual(correct, cases.count, "All meal-hint cases should parse correctly")
    }

    // MARK: - parseMultiFoodIntent: Multi-item Logging

    func testParseMultiFoodIntent_BasicCombinations() {
        let cases: [(String, Int)] = [
            ("log rice and dal", 2),
            ("I had 2 eggs and toast", 2),
            ("ate chicken, rice, and broccoli", 3),
            ("had eggs, toast, and coffee", 3),
            ("log paneer and roti for dinner", 2),
            ("ate an apple and a banana", 2),
        ]
        var correct = 0
        for (query, expectedCount) in cases {
            let normalized = InputNormalizer.normalize(query).lowercased()
            if let items = AIActionExecutor.parseMultiFoodIntent(normalized), items.count >= expectedCount {
                correct += 1
            } else {
                let items = AIActionExecutor.parseMultiFoodIntent(InputNormalizer.normalize(query).lowercased())
                print("MISS (multi-food): '\(query)' → \(items?.count ?? 0) items (expected \(expectedCount))")
            }
        }
        print("📊 parseMultiFoodIntent basic: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 multi-food miss")
    }

    // MARK: - Indian Meal Combinations (#464)

    func testParseFoodIntent_IndianMeals() {
        let indianQueries: [(String, String)] = [
            ("had paneer tikka masala", "paneer"),
            ("ate 2 idli with chutney", "idli"),
            ("log 1 dosa and sambar", "dosa"),
            ("had a plate of biryani", "biryani"),
            ("ate chole bhature", "chole"),
            ("log rajma chawal", "rajma"),
            ("had 2 parathas for breakfast", "paratha"),
            ("ate aloo gobi with rotis", "aloo"),
            ("had dal makhani and naan", "dal"),
            ("log a bowl of khichdi", "khichdi"),
        ]
        var detected = 0
        for (query, expectedKeyword) in indianQueries {
            let normalized = InputNormalizer.normalize(query).lowercased()
            let singleHit = AIActionExecutor.parseFoodIntent(normalized).map {
                $0.query.lowercased().contains(expectedKeyword) || normalized.contains(expectedKeyword)
            } ?? false
            let multiHit = AIActionExecutor.parseMultiFoodIntent(normalized) != nil
            if singleHit || multiHit { detected += 1 }
            else { print("MISS (indian meal): '\(query)'") }
        }
        print("📊 Indian meals: \(detected)/\(indianQueries.count)")
        XCTAssertGreaterThanOrEqual(detected, Int(Double(indianQueries.count) * 0.8), "Indian meals: ≥80% detection")
    }

    func testParseMultiFoodIntent_IndianCombinations() {
        let cases: [(String, Int)] = [
            ("had dal chawal", 2),
            ("ate rajma chawal", 2),
            ("log idli and sambar", 2),
            ("had roti and sabzi", 2),
            ("ate dosa with chutney", 2),
        ]
        var correct = 0
        for (query, minExpected) in cases {
            let normalized = InputNormalizer.normalize(query).lowercased()
            let multiItems = AIActionExecutor.parseMultiFoodIntent(normalized)
            let singleItem = AIActionExecutor.parseFoodIntent(normalized)
            if (multiItems?.count ?? 0) >= minExpected || singleItem != nil {
                correct += 1
            } else {
                print("MISS (indian combo): '\(query)'")
            }
        }
        print("📊 Indian multi-food combos: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 Indian combo miss")
    }

    // MARK: - ToolRanker: log_food Routing

    @MainActor
    func testToolRanker_LogFoodRouting() {
        let queries = [
            "log 2 eggs",
            "I had chicken breast",
            "ate a banana for breakfast",
            "had 200g paneer",
            "log rice for dinner",
            "ate oatmeal this morning",
            "had a protein shake",
            "drank a glass of milk",
            "eating yogurt",
            "log 3 scoops of whey",
        ]
        var correct = 0
        for query in queries {
            let normalized = InputNormalizer.normalize(query).lowercased()
            let tools = ToolRanker.rank(query: normalized, screen: .food)
            if tools.first?.name == "log_food" { correct += 1 }
            else { print("MISS (ToolRanker log_food): '\(query)' → \(tools.first?.name ?? "nil")") }
        }
        print("📊 ToolRanker log_food routing: \(correct)/\(queries.count)")
        XCTAssertGreaterThanOrEqual(correct, queries.count - 2, "At most 2 ToolRanker log_food misses")
    }

    // MARK: - False Positive Prevention

    func testParseFoodIntent_NonFoodQueriesRejected() {
        let nonFoodQueries = [
            "how many calories left",
            "what should I eat for dinner",
            "how's my protein today",
            "daily summary",
            "weekly summary",
            "calories in a banana",
            "weight trend",
            "suggest a workout",
            "how did I sleep",
            "show my macros",
            "how am I doing on protein",
            "set goal to 160 lbs",
            "did I take creatine today",
            "how many carbs left",
            "am I on track for protein",
        ]
        var falsePositives: [String] = []
        for query in nonFoodQueries {
            let normalized = InputNormalizer.normalize(query).lowercased()
            if AIActionExecutor.parseFoodIntent(normalized) != nil {
                falsePositives.append(query)
            }
        }
        if !falsePositives.isEmpty {
            print("FALSE POSITIVES:\n\(falsePositives.joined(separator: "\n"))")
        }
        XCTAssertLessThanOrEqual(falsePositives.count, 1, "At most 1 false-positive for non-food queries")
    }

    // MARK: - Voice-style Queries

    func testParseFoodIntent_VoiceStyleAfterNormalization() {
        let voiceQueries = [
            "umm I had 2 eggs",
            "so I ate some rice",
            "ok so log chicken breast",
            "well I had a banana",
            "uh just had some yogurt",
            "like I just ate an apple",
        ]
        var correct = 0
        for query in voiceQueries {
            let normalized = InputNormalizer.normalize(query).lowercased()
            if AIActionExecutor.parseFoodIntent(normalized) != nil { correct += 1 }
            else { print("MISS (voice-style): '\(query)' → '\(normalized)'") }
        }
        print("📊 parseFoodIntent voice-style: \(correct)/\(voiceQueries.count)")
        XCTAssertGreaterThanOrEqual(correct, voiceQueries.count - 1, "At most 1 voice-style miss after normalization")
    }

    // MARK: - Summary Gold Set

    func testFoodLoggingGoldSetSummary() {
        let allCases: [(String, Bool)] = [
            ("log 2 eggs", true),
            ("I had chicken breast", true),
            ("ate a banana for breakfast", true),
            ("had 200g paneer", true),
            ("log rice and dal", true),
            ("I had 2 eggs and toast", true),
            ("so I ate biryani for lunch", true),
            ("had a couple of rotis", true),
            ("ate 3 idli with chutney", true),
            ("log aloo gobi", true),
            ("had a protein shake", true),
            ("drank a glass of milk", true),
            ("eating oatmeal", true),
            ("just had some yogurt", true),
            ("log 100g chicken for dinner", true),
            ("ate chole bhature", true),
            ("had dal makhani and naan", true),
            ("log 3 scoops of protein", true),
            ("I made a smoothie", true),
            ("had some rice", true),
            ("how many calories left", false),
            ("what should I eat", false),
            ("how's my protein", false),
            ("daily summary", false),
            ("weekly summary", false),
            ("hello", false),
            ("calories in a banana", false),
            ("weight trend", false),
            ("suggest a workout", false),
            ("how am I doing", false),
            ("set goal to 160 lbs", false),
            ("did I take creatine", false),
            ("how do I do a deadlift", false),
            ("am I on track for protein", false),
            ("I weigh 165 lbs", false),
        ]

        var truePositive = 0, trueNegative = 0
        var falsePositive: [String] = [], falseNegative: [String] = []

        for (query, shouldDetect) in allCases {
            let normalized = InputNormalizer.normalize(query).lowercased()
            let detected = AIActionExecutor.parseFoodIntent(normalized) != nil
                || AIActionExecutor.parseMultiFoodIntent(normalized) != nil

            if shouldDetect && detected { truePositive += 1 }
            else if !shouldDetect && !detected { trueNegative += 1 }
            else if !shouldDetect && detected { falsePositive.append(query) }
            else { falseNegative.append(query) }
        }

        let positives = allCases.filter { $0.1 }.count
        let negatives = allCases.filter { !$0.1 }.count
        let precision = truePositive > 0 ? Double(truePositive) / Double(truePositive + falsePositive.count) * 100 : 0
        let recall = Double(truePositive) / Double(positives) * 100
        print("📊 FOOD LOGGING GOLD SET:")
        print("   Precision: \(String(format: "%.0f", precision))% (\(truePositive)/\(truePositive + falsePositive.count))")
        print("   Recall: \(String(format: "%.0f", recall))% (\(truePositive)/\(positives))")
        print("   True Negatives: \(trueNegative)/\(negatives)")
        if !falsePositive.isEmpty { print("   False Positives:\n   - \(falsePositive.joined(separator: "\n   - "))") }
        if !falseNegative.isEmpty { print("   False Negatives:\n   - \(falseNegative.joined(separator: "\n   - "))") }

        XCTAssertGreaterThanOrEqual(recall, 80, "Recall should be ≥80%")
        XCTAssertGreaterThanOrEqual(precision, 90, "Precision should be ≥90%")
    }
}
