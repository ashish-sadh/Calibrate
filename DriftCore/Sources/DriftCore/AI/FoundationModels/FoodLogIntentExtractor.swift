import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Public output type (available on all OS versions)

/// One food-logging intent extracted by the FM pipeline. Mirrors the
/// `@Generable FMFoodLogIntentSchema` below. Replaces the per-stage regex
/// chain (parseFoodIntent + parseMultiFoodIntent + extractAmount +
/// matchIngredient — ~340 LOC) with a single typed call. Indian-food bar
/// applies: prompt must handle bare-juxtaposition compounds and
/// regional units (plates, bowls) the regex doesn't cover.
public struct FMFoodLogIntent: Sendable, Equatable {
    public enum Unit: String, Sendable {
        case grams, ounces, milliliters, cups, tablespoons, teaspoons,
             pieces, slices, plates, bowls, servings
    }

    public enum MealType: String, Sendable {
        case breakfast, lunch, dinner, snack
    }

    public struct Item: Sendable, Equatable {
        public let foodName: String
        public let quantity: Double
        public let unit: Unit

        public init(foodName: String, quantity: Double, unit: Unit) {
            self.foodName = foodName
            self.quantity = quantity
            self.unit = unit
        }
    }

    public let foodName: String
    public let quantity: Double
    public let unit: Unit
    public let mealType: MealType?
    public let additionalItems: [Item]

    public init(
        foodName: String,
        quantity: Double,
        unit: Unit,
        mealType: MealType? = nil,
        additionalItems: [Item] = []
    ) {
        self.foodName = foodName
        self.quantity = quantity
        self.unit = unit
        self.mealType = mealType
        self.additionalItems = additionalItems
    }
}

public enum FMFoodLogIntentExtractorError: Error, Sendable {
    case unavailable
    case sessionFailed(String)
    /// FM produced empty `foodName` — the message wasn't a food log
    /// ("show me my weight chart", "log workout"). Caller falls through to
    /// the regex parser which has its own non-food sentinel handling.
    case notFoodLog
    /// FM returned a numeric out of plausible-meal range. Caller falls back
    /// to regex; downstream macro sanity checks would have caught it anyway.
    case bounded(field: String, value: Double)
}

// MARK: - Bounds (design-666 QW1 sanity post-extraction)

public enum FoodLogIntentBounds {
    /// 0.01 = a tiny dash (1/100 tsp). 100 = a 100-piece bag of grapes / 100g.
    /// Anything outside is a hallucination — bail to regex.
    public static let quantityRange: ClosedRange<Double> = 0.01...100
    /// Realistic ceiling for "I had X, Y, Z, ..." style messages. Above this is
    /// almost always the FM splitting one dish into ingredient words.
    public static let maxAdditionalItems: Int = 9

    public enum Violation: Equatable, Sendable {
        case notFoodLog
        case quantityOutOfRange(Double)
        case tooManyAdditionals(Int)
    }

    public static func violation(in intent: FMFoodLogIntent) -> Violation? {
        if intent.foodName.trimmingCharacters(in: .whitespaces).isEmpty {
            return .notFoodLog
        }
        if !quantityRange.contains(intent.quantity) {
            return .quantityOutOfRange(intent.quantity)
        }
        if intent.additionalItems.count > maxAdditionalItems {
            return .tooManyAdditionals(intent.additionalItems.count)
        }
        return nil
    }
}

// MARK: - Extractor

public enum FoodLogIntentExtractor {

    /// Extract a typed food-log intent from a free-text user message.
    /// Throws `.unavailable` on iOS<26 / macOS<26 or when FoundationModels is
    /// not linked; throws `.notFoodLog` when the model returns an empty
    /// foodName (non-food query); throws `.bounded` on out-of-range numerics.
    /// All throw cases tell the caller to fall back to the regex path.
    public static func extract(text: String) async throws -> FMFoodLogIntent {
#if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            let prompt = buildPrompt(for: text)
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt, generating: FMFoodLogIntentSchema.self)
                let primaryUnit = FMFoodLogIntent.Unit(rawValue: response.content.unit.lowercased()) ?? .servings
                let mealType: FMFoodLogIntent.MealType? = response.content.mealType
                    .flatMap { FMFoodLogIntent.MealType(rawValue: $0.lowercased()) }
                let intent = FMFoodLogIntent(
                    foodName: response.content.foodName,
                    quantity: response.content.quantity,
                    unit: primaryUnit,
                    mealType: mealType,
                    additionalItems: response.content.additionalItems.map {
                        FMFoodLogIntent.Item(
                            foodName: $0.foodName,
                            quantity: $0.quantity,
                            unit: FMFoodLogIntent.Unit(rawValue: $0.unit.lowercased()) ?? .servings
                        )
                    }
                )
                if let v = FoodLogIntentBounds.violation(in: intent) {
                    switch v {
                    case .notFoodLog:
                        throw FMFoodLogIntentExtractorError.notFoodLog
                    case .quantityOutOfRange(let q):
                        throw FMFoodLogIntentExtractorError.bounded(field: "quantity", value: q)
                    case .tooManyAdditionals(let n):
                        throw FMFoodLogIntentExtractorError.bounded(field: "additionalItems", value: Double(n))
                    }
                }
                return intent
            } catch let err as FMFoodLogIntentExtractorError {
                throw err
            } catch {
                throw FMFoodLogIntentExtractorError.sessionFailed("\(error)")
            }
        }
#endif
        throw FMFoodLogIntentExtractorError.unavailable
    }

    /// Prompt sent to the foundation model. Covers the eight families the
    /// regex chain juggles today across ~340 LOC: counts, weights, volumes,
    /// portions, fractions, multipliers, meal hints, and the non-food
    /// sentinel ("show me my weight chart" must return empty foodName so
    /// downstream falls through to the right tool instead of synthesizing
    /// a bogus food log).
    public static func buildPrompt(for text: String) -> String {
        """
        Parse the user's message into a structured food-logging intent.

        Quantity + unit families:
        - Counts: "2 eggs", "3 bananas" → quantity=2, unit=pieces (whole-piece foods)
        - Weights: "200g paneer", "8 oz chicken" → quantity=200, unit=grams (convert ounces×28.35 to grams ONLY if you must; otherwise return the user's literal unit and let downstream convert)
        - Volumes: "1 cup oats", "2 tbsp honey", "1 tsp ghee", "200ml milk" → keep cups/tablespoons/teaspoons/milliliters verbatim
        - Portions: "half a banana", "a quarter cup oats", "1/3 avocado" → quantity=0.5/0.25/0.333, unit matches what the user said (pieces / cups)
        - Plates / bowls / servings: "a plate of biryani", "a bowl of dal", "1 serving rice" → unit=plates/bowls/servings
        - Slices: "2 slices bread" → unit=slices
        - Multipliers: "double the rice" → quantity=2, unit=servings; "triple the eggs" → quantity=3, unit=pieces; "2x chicken" → quantity=2, unit=servings
        - No quantity: "log eggs", "ate paneer" → quantity=1, unit=servings (user didn't specify — downstream defaults to 1 serving)

        Meal hint: if the user said "for breakfast/lunch/dinner/snack", set mealType. Otherwise leave nil.

        Compound foods that LOOK like multi-food but are ONE dish — keep as a single foodName, no additionalItems:
        - "mac and cheese", "bread and butter", "salt and pepper", "rice and beans",
          "peanut butter and jelly", "fish and chips", "ham and cheese"

        Multi-food messages ("chicken and rice", "eggs, toast, and coffee") — split into primary + additionalItems. The primary is the first food mentioned. Each additional item carries its own quantity + unit.

        Non-food / data-request messages — return EMPTY foodName (downstream routes elsewhere):
        - "show me my weight chart" → foodName="", quantity=1, unit=servings
        - "log workout", "exercise", "weight", "sleep", "summary", "supplement" → foodName=""
        - "what did I eat yesterday" → foodName=""

        Conversational / greeting / off-topic messages — also return EMPTY foodName.
        Real bug from the field 2026-05-21: speech transcribed "hello how are you
        doing" and the extractor hallucinated egg + banana. If the message contains
        no explicit food item or quantity, foodName must be the empty string.
        Examples that must return foodName="":
        - "hello", "hi", "hey there", "good morning", "good evening"
        - "how are you", "how are you doing", "what's up"
        - "what can you do", "help", "test", "testing"
        - Any greeting, question, or smalltalk without a named food

        Food name rules:
        - Use singular canonical form: "egg" not "eggs", "banana" not "bananas".
        - Preserve the user's specific dish name verbatim (e.g. "chicken biryani" stays one phrase, not split into chicken + biryani).
        - Do NOT invent foods the user didn't mention.

        Text:

        \(text)
        """
    }
}

// MARK: - Generable schema (compiled only on macOS 26+ / iOS 26+)

#if canImport(FoundationModels)
@available(macOS 26, iOS 26, *)
@Generable
struct FMFoodLogIntentSchema: Sendable {
    @Guide(description: "Primary food name in singular canonical form (e.g. 'egg', 'banana', 'chicken biryani'). EMPTY STRING when the message is not a food log — covers BOTH data requests (weight chart, workout, summary, etc.) AND conversational input (greetings like 'hello' or 'how are you doing', help requests, smalltalk). Do not invent a food when the user did not name one.")
    let foodName: String
    @Guide(description: "Numeric quantity. Use 1 when the user didn't specify. Range 0.01-100.")
    let quantity: Double
    @Guide(description: "Unit of measurement, one of: 'grams', 'ounces', 'milliliters', 'cups', 'tablespoons', 'teaspoons', 'pieces', 'slices', 'plates', 'bowls', 'servings'. Use 'servings' as a fallback when the user didn't specify.")
    let unit: String
    @Guide(description: "Meal type literal: 'breakfast', 'lunch', 'dinner', or 'snack'. Nil when the user did not name a meal.")
    let mealType: String?
    @Guide(description: "Additional foods the user mentioned in the same message; empty array when only one food was named. Compound foods like 'mac and cheese' stay as a single primary, NOT split.")
    let additionalItems: [Item]

    @Generable
    struct Item: Sendable {
        @Guide(description: "Food name in singular canonical form. Do not invent foods the user didn't mention.")
        let foodName: String
        @Guide(description: "Numeric quantity for this item. Use 1 when not specified.")
        let quantity: Double
        @Guide(description: "Unit literal, same vocabulary as the primary unit.")
        let unit: String
    }
}
#endif
