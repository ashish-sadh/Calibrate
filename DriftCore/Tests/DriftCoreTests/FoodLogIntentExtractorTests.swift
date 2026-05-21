import Foundation
@testable import DriftCore
import Testing

// Tier-0 tests for design-666 QW1 unified food-log intent extractor.
// Pure helpers only — bounds + 10 prompt anchors + flag default + bridge
// mapping + 40-row gold set + flag-off async↔sync equivalence. The FM-backed
// Tier-3 gold set lives in DriftLLMEvalMacOS (extension lands separately).

// MARK: - FoodLogIntentBounds — hallucination guard

@Test func foodIntentBounds_simpleClean() {
    let i = FMFoodLogIntent(foodName: "egg", quantity: 2, unit: .pieces)
    #expect(FoodLogIntentBounds.violation(in: i) == nil)
}

@Test func foodIntentBounds_thaliCeilingOK() {
    // 9 additionals = the realistic ceiling. Should pass.
    let items = (0..<9).map { FMFoodLogIntent.Item(foodName: "item\($0)", quantity: 1, unit: .servings) }
    let i = FMFoodLogIntent(foodName: "biryani", quantity: 1, unit: .plates, additionalItems: items)
    #expect(FoodLogIntentBounds.violation(in: i) == nil)
}

@Test func foodIntentBounds_emptyFoodNameNotFoodLog() {
    let i = FMFoodLogIntent(foodName: "", quantity: 1, unit: .servings)
    #expect(FoodLogIntentBounds.violation(in: i) == .notFoodLog)
}

@Test func foodIntentBounds_whitespaceFoodNameNotFoodLog() {
    let i = FMFoodLogIntent(foodName: "   ", quantity: 1, unit: .servings)
    #expect(FoodLogIntentBounds.violation(in: i) == .notFoodLog)
}

@Test func foodIntentBounds_rejectZeroQuantity() {
    let i = FMFoodLogIntent(foodName: "rice", quantity: 0, unit: .grams)
    #expect(FoodLogIntentBounds.violation(in: i) == .quantityOutOfRange(0))
}

@Test func foodIntentBounds_rejectImpossibleQuantity() {
    let i = FMFoodLogIntent(foodName: "rice", quantity: 9999, unit: .grams)
    #expect(FoodLogIntentBounds.violation(in: i) == .quantityOutOfRange(9999))
}

@Test func foodIntentBounds_rejectIngredientHallucination() {
    // FM splitting "chicken biryani" into 10+ ingredient words = hallucination.
    let items = (0..<10).map { FMFoodLogIntent.Item(foodName: "item\($0)", quantity: 1, unit: .servings) }
    let i = FMFoodLogIntent(foodName: "biryani", quantity: 1, unit: .plates, additionalItems: items)
    #expect(FoodLogIntentBounds.violation(in: i) == .tooManyAdditionals(10))
}

@Test func foodIntentBounds_minQuantityOK() {
    let i = FMFoodLogIntent(foodName: "saffron", quantity: 0.01, unit: .grams)
    #expect(FoodLogIntentBounds.violation(in: i) == nil)
}

@Test func foodIntentBounds_maxQuantityOK() {
    let i = FMFoodLogIntent(foodName: "grapes", quantity: 100, unit: .pieces)
    #expect(FoodLogIntentBounds.violation(in: i) == nil)
}

// MARK: - Feature flag default (serialized — both tests touch one UserDefaults key)

@Suite(.serialized) struct FoodIntentFlagBehavior {
    private let key = "drift_fm_food_intent_extract"

    @Test func defaultsAndPersistence() {
        defer { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        #expect(Preferences.fmFoodIntentExtractEnabled == true,
                "Per design-666 QW1 the FM food-intent path defaults ON")

        Preferences.fmFoodIntentExtractEnabled = false
        #expect(Preferences.fmFoodIntentExtractEnabled == false)
        Preferences.fmFoodIntentExtractEnabled = true
        #expect(Preferences.fmFoodIntentExtractEnabled == true)
    }

    @Test func asyncParseFood_flagOffMatchesSync() async {
        defer { UserDefaults.standard.removeObject(forKey: key) }
        Preferences.fmFoodIntentExtractEnabled = false
        let input = "ate 2 eggs"
        let asyncResult = await AIActionExecutor.parseFoodIntentAsync(input)
        let syncResult = AIActionExecutor.parseFoodIntent(input)
        #expect(equalIntents(asyncResult, syncResult),
                "Flag-off async path must match sync regex output exactly")
    }

    @Test func asyncMultiFood_flagOffMatchesSync() async {
        defer { UserDefaults.standard.removeObject(forKey: key) }
        Preferences.fmFoodIntentExtractEnabled = false
        let input = "ate chicken and rice"
        let asyncResult = await AIActionExecutor.parseMultiFoodIntentAsync(input)
        let syncResult = AIActionExecutor.parseMultiFoodIntent(input)
        #expect(equalIntentArrays(asyncResult, syncResult),
                "Flag-off async multi-food path must match sync regex output exactly")
    }

    @Test func asyncParseFood_flagOffMatchesSync_allGoldRows() async {
        // Exhaustive flag-off equivalence: every gold-set row must round-trip
        // identically through parseFoodIntentAsync vs parseFoodIntent. Pins
        // the kill-switch guarantee: when fmFoodIntentExtractEnabled is false,
        // the async path is byte-for-byte the sync regex with zero FM influence.
        defer { UserDefaults.standard.removeObject(forKey: key) }
        Preferences.fmFoodIntentExtractEnabled = false
        for row in foodIntentGoldSet {
            let asyncResult = await AIActionExecutor.parseFoodIntentAsync(row.input)
            let syncResult = AIActionExecutor.parseFoodIntent(row.input)
            #expect(equalIntents(asyncResult, syncResult),
                    "Flag-off divergence on '\(row.input)' — async=\(intentString(asyncResult)), sync=\(intentString(syncResult))")
        }
    }
}

// MARK: - Prompt anchoring (10 distinct anchor families per design-666 QW1)

@Test func foodIntentPromptCoversCountUnit() {
    let p = FoodLogIntentExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("pieces"))
}

@Test func foodIntentPromptCoversWeightUnit() {
    let p = FoodLogIntentExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("grams"))
}

@Test func foodIntentPromptCoversVolumeUnit() {
    let p = FoodLogIntentExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("tbsp") || p.contains("tablespoons"))
    #expect(p.contains("cup") || p.contains("cups"))
}

@Test func foodIntentPromptCoversPortionWord() {
    // "half a banana", "quarter cup oats" — regex stumbles, FM handles.
    let p = FoodLogIntentExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("half") || p.contains("quarter"))
}

@Test func foodIntentPromptCoversFraction() {
    // "1/3 avocado" — fraction parsing.
    let p = FoodLogIntentExtractor.buildPrompt(for: "any")
    #expect(p.contains("1/3") || p.lowercased().contains("0.333"))
}

@Test func foodIntentPromptCoversMultiplier() {
    let p = FoodLogIntentExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("double") || p.contains("triple") || p.contains("2x"))
}

@Test func foodIntentPromptCoversMealHint() {
    let p = FoodLogIntentExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("breakfast"))
    #expect(p.contains("mealtype"))
}

@Test func foodIntentPromptCoversCompoundFoodWhitelist() {
    // Compound foods MUST stay as one — "mac and cheese" → one foodName.
    // Without this guard the model splits compound dishes into ingredient words.
    let p = FoodLogIntentExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("mac and cheese"))
}

@Test func foodIntentPromptCoversNonFoodSentinel() {
    // Empty foodName is the "not a food log" signal — must be explicit so the
    // bounds violation lands instead of synthesizing a bogus log row.
    let p = FoodLogIntentExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("empty"))
    #expect(p.contains("weight chart") || p.contains("workout"))
}

@Test func foodIntentPromptCoversGreetings() {
    // Real field bug 2026-05-21: speech said "Hello how are you doing" and
    // the extractor returned egg + banana. Pin the greeting examples in the
    // prompt so subsequent edits can't silently drop them and reintroduce
    // the hallucination. Doesn't simulate the FM (Tier 3 territory) — just
    // pins the prompt content the FM sees.
    let p = FoodLogIntentExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("hello"))
    #expect(p.contains("how are you"))
    #expect(p.contains("greeting") || p.contains("smalltalk") || p.contains("conversational"))
}

@Test func foodIntentPromptIncludesInputText() {
    let unique = "MARKER_\(UUID().uuidString.prefix(8))"
    let p = FoodLogIntentExtractor.buildPrompt(for: unique)
    #expect(p.contains(unique))
}

@Test func foodIntentPromptForbidsInvention() {
    // FM must not invent foods the user didn't say — strict guardrail since
    // hallucinated food rows log calories the user never ate.
    let p = FoodLogIntentExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("do not invent") || p.contains("don't invent") || p.contains("verbatim"))
}

// MARK: - FoodLogIntentBridge — unit → FoodIntent mapping

@Test func bridge_gramsStayGrams() {
    let i = FMFoodLogIntent(foodName: "chicken", quantity: 200, unit: .grams)
    let out = FoodLogIntentBridge.toFoodIntent(i)
    #expect(out.query == "chicken")
    #expect(out.gramAmount == 200)
    #expect(out.servings == nil)
}

@Test func bridge_ouncesConvertToGrams() {
    let i = FMFoodLogIntent(foodName: "almonds", quantity: 2, unit: .ounces)
    let out = FoodLogIntentBridge.toFoodIntent(i)
    // 2 oz × 28.3495 ≈ 56.7
    #expect(out.gramAmount.map { abs($0 - 56.699) < 0.01 } ?? false)
    #expect(out.servings == nil)
}

@Test func bridge_millilitersStayAsGrams() {
    let i = FMFoodLogIntent(foodName: "milk", quantity: 100, unit: .milliliters)
    let out = FoodLogIntentBridge.toFoodIntent(i)
    #expect(out.gramAmount == 100)
}

@Test func bridge_cupsUseFoodAwareDensity() {
    // 1 cup oats = 80g (gramsPerCup for oats). NOT 240g (flat-cup constant).
    let i = FMFoodLogIntent(foodName: "oats", quantity: 1, unit: .cups)
    let out = FoodLogIntentBridge.toFoodIntent(i)
    #expect(out.query == "oat")
    #expect(out.gramAmount == 80, "1 cup oats must use oats density (80g), not flat 240g")
}

@Test func bridge_cupsUnknownFoodFallback() {
    // Food not in matchIngredient table → falls back to flat 240g.
    let i = FMFoodLogIntent(foodName: "tuna", quantity: 1, unit: .cups)
    let out = FoodLogIntentBridge.toFoodIntent(i)
    #expect(out.gramAmount == 240, "Unknown food in cups uses flat 240g fallback")
}

@Test func bridge_tablespoonsUseFoodAwareDensity() {
    // 2 tbsp honey = 2 × (340/16) = 42.5g.
    let i = FMFoodLogIntent(foodName: "honey", quantity: 2, unit: .tablespoons)
    let out = FoodLogIntentBridge.toFoodIntent(i)
    #expect(out.gramAmount.map { abs($0 - 42.5) < 0.01 } ?? false)
}

@Test func bridge_teaspoonsUseFoodAwareDensity() {
    // 1 tsp ghee = 1 × (218/48) ≈ 4.54g.
    let i = FMFoodLogIntent(foodName: "ghee", quantity: 1, unit: .teaspoons)
    let out = FoodLogIntentBridge.toFoodIntent(i)
    #expect(out.gramAmount.map { abs($0 - 4.54) < 0.05 } ?? false)
}

@Test func bridge_piecesResolveToGramsForKnownFood() {
    // 2 eggs → 2 × 50g (egg gramsPerPiece) = 100g.
    let i = FMFoodLogIntent(foodName: "egg", quantity: 2, unit: .pieces)
    let out = FoodLogIntentBridge.toFoodIntent(i)
    #expect(out.gramAmount == 100)
    #expect(out.servings == nil)
}

@Test func bridge_piecesUnknownFoodStayAsServings() {
    // FM said "pieces" but food has no known piece weight (e.g. "samosa")
    // → keep as servings so downstream still logs *something* sensible.
    let i = FMFoodLogIntent(foodName: "samosa", quantity: 3, unit: .pieces)
    let out = FoodLogIntentBridge.toFoodIntent(i)
    #expect(out.servings == 3)
    #expect(out.gramAmount == nil)
}

@Test func bridge_slicesAreServings() {
    // 2 slices of bread → 2 servings (slice has no flat gram constant
    // since bread slice weight varies wildly).
    let i = FMFoodLogIntent(foodName: "bread", quantity: 2, unit: .slices)
    let out = FoodLogIntentBridge.toFoodIntent(i)
    #expect(out.servings == 2)
    #expect(out.gramAmount == nil)
}

@Test func bridge_platesAndBowlsAreServings() {
    let plate = FoodLogIntentBridge.toFoodIntent(
        FMFoodLogIntent(foodName: "biryani", quantity: 1, unit: .plates)
    )
    #expect(plate.servings == 1)
    #expect(plate.gramAmount == nil)

    let bowl = FoodLogIntentBridge.toFoodIntent(
        FMFoodLogIntent(foodName: "dal", quantity: 1, unit: .bowls)
    )
    #expect(bowl.servings == 1)
    #expect(bowl.gramAmount == nil)
}

@Test func bridge_pluralsSingularized() {
    // FM might return "eggs" (plural) — bridge singularizes to match
    // regex parser output and DB lookup expectations.
    let i = FMFoodLogIntent(foodName: "bananas", quantity: 2, unit: .pieces)
    let out = FoodLogIntentBridge.toFoodIntent(i)
    #expect(out.query == "banana")
}

@Test func bridge_singularNotMutated() {
    // Don't singularize words that already are singular (e.g. "rice" ends in 'e').
    let i = FMFoodLogIntent(foodName: "rice", quantity: 100, unit: .grams)
    let out = FoodLogIntentBridge.toFoodIntent(i)
    #expect(out.query == "rice")
}

@Test func bridge_shortWordsNotSingularized() {
    // "gas" is 3 chars — don't strip 's' (would mangle short words).
    let i = FMFoodLogIntent(foodName: "gas", quantity: 1, unit: .servings)
    let out = FoodLogIntentBridge.toFoodIntent(i)
    #expect(out.query == "gas")
}

@Test func bridge_mealHintInheritedByAdditionals() {
    // "ate eggs and toast for breakfast" — bridge propagates breakfast
    // mealHint to BOTH the primary egg intent and the toast additional.
    let i = FMFoodLogIntent(
        foodName: "egg",
        quantity: 2,
        unit: .pieces,
        mealType: .breakfast,
        additionalItems: [
            .init(foodName: "toast", quantity: 1, unit: .slices)
        ]
    )
    let intents = FoodLogIntentBridge.toFoodIntents(i)
    #expect(intents.count == 2)
    #expect(intents[0].mealHint == "breakfast")
    #expect(intents[1].mealHint == "breakfast",
            "Additional items must inherit mealHint from the primary")
}

@Test func bridge_nilMealHintNotInjected() {
    // No mealType from FM → both primary and additionals carry nil mealHint.
    let i = FMFoodLogIntent(
        foodName: "egg", quantity: 2, unit: .pieces, mealType: nil,
        additionalItems: [.init(foodName: "toast", quantity: 1, unit: .slices)]
    )
    let intents = FoodLogIntentBridge.toFoodIntents(i)
    #expect(intents.allSatisfy { $0.mealHint == nil })
}

@Test func bridge_singleIntent_extractedOnly() {
    // toFoodIntent returns ONLY the primary — used by parseFoodIntentAsync
    // which expects a single intent.
    let i = FMFoodLogIntent(
        foodName: "chicken", quantity: 1, unit: .servings,
        additionalItems: [
            .init(foodName: "rice", quantity: 1, unit: .cups),
            .init(foodName: "broccoli", quantity: 1, unit: .servings),
        ]
    )
    let out = FoodLogIntentBridge.toFoodIntent(i)
    #expect(out.query == "chicken")
}

// MARK: - Gold set — 40 food-log queries (design-666 QW1 deliverable)

/// What the FM extractor should produce (specification), expressed as a
/// `FoodIntent`. Use `_anyQuantity` when the specific numeric is unstable
/// across FM revisions — only the shape matters.
private struct FoodTarget: Equatable, Sendable {
    let query: String
    let servings: Double?
    let gramAmount: Double?
    let mealHint: String?
}

/// `match(target)` — regex matches and equals `target` (regex correct today)
/// `wrong(observed)` — regex returns *something* but differs from target (FM win: correctness)
/// `miss` — regex returns nil but target is non-nil (FM win: coverage)
/// `correctlyRejected` — regex returns nil and target is also nil (parity, both punt)
private enum RegexBaseline: Equatable {
    case match
    case wrong(observed: FoodTarget)
    case miss
    case correctlyRejected
}

private struct FoodRow {
    let input: String
    let target: FoodTarget?
    let regexBaseline: RegexBaseline
}

private let foodIntentGoldSet: [FoodRow] = [
    // 1-8: counts (regex handles correctly)
    .init(input: "ate 2 eggs", target: .init(query: "egg", servings: 2, gramAmount: nil, mealHint: nil), regexBaseline: .match),
    .init(input: "log 3 bananas", target: .init(query: "banana", servings: 3, gramAmount: nil, mealHint: nil), regexBaseline: .match),
    .init(input: "had 4 chapatis", target: .init(query: "chapati", servings: 4, gramAmount: nil, mealHint: nil), regexBaseline: .match),
    .init(input: "ate 5 dosas", target: .init(query: "dosa", servings: 5, gramAmount: nil, mealHint: nil), regexBaseline: .match),
    .init(input: "ate eggs", target: .init(query: "egg", servings: nil, gramAmount: nil, mealHint: nil), regexBaseline: .match),
    .init(input: "log paneer", target: .init(query: "paneer", servings: nil, gramAmount: nil, mealHint: nil), regexBaseline: .match),
    .init(input: "had toast", target: .init(query: "toast", servings: nil, gramAmount: nil, mealHint: nil), regexBaseline: .match),
    .init(input: "ate one egg", target: .init(query: "egg", servings: 1, gramAmount: nil, mealHint: nil), regexBaseline: .match),

    // 9-13: weights (regex handles correctly)
    .init(input: "log 200g chicken", target: .init(query: "chicken", servings: nil, gramAmount: 200, mealHint: nil), regexBaseline: .match),
    .init(input: "ate 100g paneer", target: .init(query: "paneer", servings: nil, gramAmount: 100, mealHint: nil), regexBaseline: .match),
    .init(input: "log 2 oz almonds", target: .init(query: "almond", servings: nil, gramAmount: 56.699, mealHint: nil), regexBaseline: .match),
    .init(input: "had 50g rice", target: .init(query: "rice", servings: nil, gramAmount: 50, mealHint: nil), regexBaseline: .match),
    .init(input: "log 1kg oats", target: .init(query: "oat", servings: nil, gramAmount: 1000, mealHint: nil), regexBaseline: .match),

    // 14-18: volumes (regex handles correctly with food-aware density)
    .init(input: "log 1 cup oats", target: .init(query: "oat", servings: nil, gramAmount: 80, mealHint: nil), regexBaseline: .match),
    .init(input: "ate 2 tbsp honey", target: .init(query: "honey", servings: nil, gramAmount: 42.5, mealHint: nil), regexBaseline: .match),
    .init(input: "log 1 tsp ghee", target: .init(query: "ghee", servings: nil, gramAmount: 218.0 / 48.0, mealHint: nil), regexBaseline: .match),
    .init(input: "had 100ml milk", target: .init(query: "milk", servings: nil, gramAmount: 100, mealHint: nil), regexBaseline: .match),
    .init(input: "log 1 cup rice", target: .init(query: "rice", servings: nil, gramAmount: 185, mealHint: nil), regexBaseline: .match),

    // 19-23: fractions / portion words
    .init(input: "log 1/3 avocado", target: .init(query: "avocado", servings: 1.0 / 3.0, gramAmount: nil, mealHint: nil), regexBaseline: .match),
    .init(input: "ate half a banana",
          target: .init(query: "banana", servings: 0.5, gramAmount: nil, mealHint: nil),
          regexBaseline: .wrong(observed: .init(query: "a banana", servings: 0.5, gramAmount: nil, mealHint: nil))),
    .init(input: "log a quarter cup oats", target: .init(query: "oat", servings: nil, gramAmount: 20, mealHint: nil), regexBaseline: .match),
    .init(input: "log a couple of eggs", target: .init(query: "egg", servings: 2, gramAmount: nil, mealHint: nil), regexBaseline: .match),
    .init(input: "ate a few almonds", target: .init(query: "almond", servings: 3, gramAmount: nil, mealHint: nil), regexBaseline: .match),

    // 24-27: multipliers
    .init(input: "log double the rice", target: .init(query: "rice", servings: 2, gramAmount: nil, mealHint: nil), regexBaseline: .match),
    .init(input: "ate 2x chicken", target: .init(query: "chicken", servings: 2, gramAmount: nil, mealHint: nil), regexBaseline: .match),
    .init(input: "log triple the eggs", target: .init(query: "egg", servings: 3, gramAmount: nil, mealHint: nil), regexBaseline: .match),
    .init(input: "ate twice the dal", target: .init(query: "dal", servings: 2, gramAmount: nil, mealHint: nil), regexBaseline: .match),

    // 28-31: meal hints
    .init(input: "log eggs for breakfast", target: .init(query: "egg", servings: nil, gramAmount: nil, mealHint: "breakfast"), regexBaseline: .match),
    .init(input: "ate rice for lunch", target: .init(query: "rice", servings: nil, gramAmount: nil, mealHint: "lunch"), regexBaseline: .match),
    .init(input: "had dal for dinner", target: .init(query: "dal", servings: nil, gramAmount: nil, mealHint: "dinner"), regexBaseline: .match),
    .init(input: "log paneer for snack", target: .init(query: "paneer", servings: nil, gramAmount: nil, mealHint: "snack"), regexBaseline: .match),

    // 32-34: compound-food whitelist — must stay as one foodName, not split
    .init(input: "ate mac and cheese", target: .init(query: "mac and cheese", servings: nil, gramAmount: nil, mealHint: nil), regexBaseline: .match),
    .init(input: "had peanut butter and jelly", target: .init(query: "peanut butter and jelly", servings: nil, gramAmount: nil, mealHint: nil), regexBaseline: .match),
    .init(input: "log bread and butter", target: .init(query: "bread and butter", servings: nil, gramAmount: nil, mealHint: nil), regexBaseline: .match),

    // 35-37: non-food sentinels — both regex and FM should return nil
    .init(input: "show me my weight chart", target: nil, regexBaseline: .correctlyRejected),
    .init(input: "log my weight", target: nil, regexBaseline: .correctlyRejected),
    .init(input: "what did I eat yesterday", target: nil, regexBaseline: .correctlyRejected),

    // 38-40: regex misses (no verb prefix or unknown unit) — FM should succeed
    .init(input: "200g chicken",
          target: .init(query: "chicken", servings: nil, gramAmount: 200, mealHint: nil),
          regexBaseline: .miss),
    .init(input: "a plate of biryani",
          target: .init(query: "biryani", servings: 1, gramAmount: nil, mealHint: nil),
          regexBaseline: .miss),
    .init(input: "a bowl of dal",
          target: .init(query: "dal", servings: 1, gramAmount: nil, mealHint: nil),
          regexBaseline: .miss),
]

@Test func foodGoldSet_hasFortyQueries() {
    #expect(foodIntentGoldSet.count == 40,
            "design-666 QW1 deliverable specifies 40 food-log gold queries")
}

@Test func foodGoldSet_regexBaselineMatchesReality() {
    // For every gold-set row, the current regex output must agree with the
    // recorded `regexBaseline`. This pins what the regex does today so a
    // future regex tweak can't silently shift the FM-vs-regex split.
    for row in foodIntentGoldSet {
        let observed = AIActionExecutor.parseFoodIntent(row.input)
        switch row.regexBaseline {
        case .match:
            guard let target = row.target else {
                #expect(Bool(false), "Row '\(row.input)' marked .match but target is nil")
                continue
            }
            #expect(intentMatchesTarget(observed, target),
                    "Regex baseline drift on '\(row.input)' — expected match \(target), got \(intentString(observed))")
        case .wrong(let observedTarget):
            #expect(intentMatchesTarget(observed, observedTarget),
                    "Regex baseline drift on '\(row.input)' — recorded wrong-output \(observedTarget), got \(intentString(observed))")
        case .miss:
            #expect(observed == nil,
                    "Regex baseline drift on '\(row.input)' — recorded miss, got \(intentString(observed))")
        case .correctlyRejected:
            #expect(observed == nil,
                    "Regex baseline drift on '\(row.input)' — recorded correctly-rejected, got \(intentString(observed))")
        }
    }
}

@Test func foodGoldSet_fmWinsCoverDistinctCategories() {
    // The FM-vs-regex delta is the QW1 win surface. Make sure the gold set
    // covers BOTH win categories — regex coverage gaps (no-verb, unknown
    // units) and regex correctness errors (portion-word stumbles). If we
    // drop below this floor the gold set isn't actually testing the migration.
    let misses = foodIntentGoldSet.filter { if case .miss = $0.regexBaseline { return true } else { return false } }
    let wrongs = foodIntentGoldSet.filter { if case .wrong = $0.regexBaseline { return true } else { return false } }
    let rejects = foodIntentGoldSet.filter { if case .correctlyRejected = $0.regexBaseline { return true } else { return false } }
    #expect(misses.count >= 2, "Need ≥2 regex-miss rows so FM coverage gain is measurable")
    #expect(wrongs.count >= 1, "Need ≥1 regex-wrong row so FM correctness gain is measurable")
    #expect(rejects.count >= 2, "Need ≥2 non-food rows so the bounds check is exercised")
}

// MARK: - Helpers

private func equalIntents(_ a: FoodIntent?, _ b: FoodIntent?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case (let l?, let r?):
        return l.query == r.query
            && l.servings == r.servings
            && l.mealHint == r.mealHint
            && l.gramAmount == r.gramAmount
    default: return false
    }
}

private func equalIntentArrays(_ a: [FoodIntent]?, _ b: [FoodIntent]?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case (let l?, let r?):
        guard l.count == r.count else { return false }
        return zip(l, r).allSatisfy { equalIntents($0, $1) }
    default: return false
    }
}

private func intentMatchesTarget(_ intent: FoodIntent?, _ target: FoodTarget) -> Bool {
    guard let i = intent else { return false }
    guard i.query == target.query else { return false }
    guard nearlyEqual(i.servings, target.servings) else { return false }
    guard nearlyEqual(i.gramAmount, target.gramAmount) else { return false }
    guard i.mealHint == target.mealHint else { return false }
    return true
}

private func nearlyEqual(_ a: Double?, _ b: Double?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case (let l?, let r?): return abs(l - r) < 0.01
    default: return false
    }
}

private func intentString(_ intent: FoodIntent?) -> String {
    guard let i = intent else { return "nil" }
    let servingsStr = i.servings.map { String($0) } ?? "nil"
    let gramsStr = i.gramAmount.map { String($0) } ?? "nil"
    let mealStr = i.mealHint ?? "nil"
    return "FoodIntent(query=\(i.query), servings=\(servingsStr), grams=\(gramsStr), meal=\(mealStr))"
}
