import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Public output type (available on all OS versions)

/// Nutrition facts extracted by the FM pipeline. Same shape as
/// `NutritionLabelOCR.ExtractedNutrition` so callers can convert without
/// loss; we keep this in DriftCore so non-iOS surfaces (eval harness,
/// macOS tooling) can use it directly.
public struct FMNutritionResult: Sendable, Equatable {
    public let name: String
    public let servingSize: String
    public let calories: Int
    public let proteinG: Double
    public let carbsG: Double
    public let fatG: Double
    public let fiberG: Double
    public let sugarG: Double
    public let sodiumMg: Double

    public init(
        name: String, servingSize: String,
        calories: Int, proteinG: Double, carbsG: Double, fatG: Double,
        fiberG: Double, sugarG: Double, sodiumMg: Double
    ) {
        self.name = name
        self.servingSize = servingSize
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.sodiumMg = sodiumMg
    }
}

public enum FMNutritionExtractorError: Error, Sendable {
    case unavailable
    case sessionFailed(String)
    case bounded(field: String, value: Double)
}

// MARK: - Bounds checks (design-665 edge case "Hallucinated critical numerics")

public enum NutritionBounds {
    public static let caloriesRange: ClosedRange<Double> = 0...5000
    public static let proteinRange: ClosedRange<Double> = 0...200
    public static let macroGramRange: ClosedRange<Double> = 0...500   // carbs/fat/fiber/sugar
    public static let sodiumMgRange: ClosedRange<Double> = 0...10_000

    /// Returns nil when every critical field is in-range; otherwise the
    /// first offending field name (so the caller can log + drop or fall back).
    public static func violation(in r: FMNutritionResult) -> String? {
        if !caloriesRange.contains(Double(r.calories)) { return "calories" }
        if !proteinRange.contains(r.proteinG) { return "proteinG" }
        if !macroGramRange.contains(r.carbsG) { return "carbsG" }
        if !macroGramRange.contains(r.fatG) { return "fatG" }
        if !macroGramRange.contains(r.fiberG) { return "fiberG" }
        if !macroGramRange.contains(r.sugarG) { return "sugarG" }
        if !sodiumMgRange.contains(r.sodiumMg) { return "sodiumMg" }
        return nil
    }
}

// MARK: - Atwater energy/macro consistency (barcode + OCR + USDA import guard)

/// Guards against the failure mode where a food's stated energy disagrees with
/// the energy implied by its macros — the classic symptom of a source that
/// paired a per-serving calorie figure with per-100g macros, or shipped a bad
/// crowd-sourced energy field. Reported 2026-07-30: a barcode scan of "aloo
/// bhujia" returned 130 kcal alongside 8P/41C/47F per 100g, which by Atwater
/// (4/4/9) is ~619 kcal — the label itself reads 624.
///
/// All values must share ONE basis (all per-100g, or all per-serving) — the
/// ratio is what matters, so callers can check either the raw source struct or
/// the scaled `Food` as long as energy and macros were scaled together.
public enum AtwaterCheck {
    /// Relative gap between stated and macro-implied energy above which we stop
    /// trusting the stated figure. 25% comfortably clears the normal noise from
    /// rounding and sugar alcohols; the fiber discount below handles high-fiber
    /// foods so the tolerance doesn't have to.
    public static let tolerance = 0.25

    /// Below this macro-implied energy there isn't enough signal to judge the
    /// stated calories (a drink logged as calories-only, an all-zero macro row).
    public static let minSignalKcal = 20.0

    /// Energy (kcal) implied by macros. Protein and carbohydrate at 4 kcal/g,
    /// fat at 9. Dietary fiber is part of total carbohydrate on a label but is
    /// only ~2 kcal/g, so we discount it — without this, high-fiber foods
    /// (psyllium, bran) look "inconsistent" and would be wrongly rewritten.
    public static func computedCalories(proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double = 0) -> Double {
        let p = max(0, proteinG)
        let f = max(0, fatG)
        let c = max(0, carbsG)
        let fib = min(max(0, fiberG), c)          // fiber can't exceed total carbohydrate
        return p * 4 + (c - fib) * 4 + fib * 2 + f * 9
    }

    /// True when the stated energy is consistent with the macros — or when
    /// there isn't enough macro signal to say. Callers that only want to log a
    /// mismatch (rather than rewrite it) use this directly.
    public static func isConsistent(stated: Double, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double = 0) -> Bool {
        let computed = computedCalories(proteinG: proteinG, carbsG: carbsG, fatG: fatG, fiberG: fiberG)
        guard computed >= minSignalKcal else { return true }   // not enough signal to judge
        guard stated > 0 else { return false }                 // real macros, no energy → inconsistent
        return abs(stated - computed) / computed <= tolerance
    }

    /// The energy we should actually store. When the macros disagree with the
    /// stated energy by more than `tolerance` (and there is macro signal to
    /// trust), prefer the macro-implied value; otherwise keep the stated one.
    /// Preferring the computed value beats rejecting the record outright: the
    /// user still gets a usable, self-consistent entry from a barcode scan.
    public static func reconciledCalories(stated: Double, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double = 0) -> Double {
        guard !isConsistent(stated: stated, proteinG: proteinG, carbsG: carbsG, fatG: fatG, fiberG: fiberG) else { return stated }
        return computedCalories(proteinG: proteinG, carbsG: carbsG, fatG: fatG, fiberG: fiberG).rounded()
    }
}

// MARK: - Extractor

public enum NutritionExtractor {

    /// Run the FM extractor against OCR text. Throws `.unavailable` when
    /// iOS<26/macOS<26 or FoundationModels isn't linked; throws
    /// `.bounded(field:value:)` when a critical numeric is out of range
    /// (caller falls back to regex). Otherwise returns the parsed facts.
    public static func extract(text: String) async throws -> FMNutritionResult {
#if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            let prompt = buildPrompt(for: text)
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt, generating: FMNutritionFacts.self)
                let result = FMNutritionResult(
                    name: response.content.name,
                    servingSize: response.content.servingSize,
                    calories: response.content.calories,
                    proteinG: response.content.proteinG,
                    carbsG: response.content.carbsG,
                    fatG: response.content.fatG,
                    fiberG: response.content.fiberG,
                    sugarG: response.content.sugarG,
                    sodiumMg: response.content.sodiumMg
                )
                if let bad = NutritionBounds.violation(in: result) {
                    let badValue: Double
                    switch bad {
                    case "calories": badValue = Double(result.calories)
                    case "proteinG": badValue = result.proteinG
                    case "carbsG": badValue = result.carbsG
                    case "fatG": badValue = result.fatG
                    case "fiberG": badValue = result.fiberG
                    case "sugarG": badValue = result.sugarG
                    case "sodiumMg": badValue = result.sodiumMg
                    default: badValue = .nan
                    }
                    throw FMNutritionExtractorError.bounded(field: bad, value: badValue)
                }
                return result
            } catch let err as FMNutritionExtractorError {
                throw err
            } catch {
                throw FMNutritionExtractorError.sessionFailed("\(error)")
            }
        }
#endif
        throw FMNutritionExtractorError.unavailable
    }

    /// Prompt sent to the foundation model. Multilingual instruction +
    /// canonical units (kcal, grams, milligrams) so the model emits a
    /// consistent shape even for Spanish/Hindi/Tamil labels.
    public static func buildPrompt(for text: String) -> String {
        """
        Extract nutrition facts from the following nutrition-label OCR text. Labels may be in any language (English, Spanish, Hindi, Tamil, etc.) — translate to canonical English fields and canonical units (calories in kcal, macros in grams, sodium in milligrams).

        Required fields: name (product name if printed, else empty), servingSize (verbatim, e.g. "1 Bar (68g)"), calories (kcal), proteinG, carbsG, fatG, fiberG, sugarG, sodiumMg. If a field is not printed, return 0.

        Treat "<1 g" as 0.5. Treat "0 g" as 0. Do not invent values.

        Text:

        \(text)
        """
    }
}

// MARK: - Generable schema (compiled only on macOS 26+ / iOS 26+)

#if canImport(FoundationModels)
@available(macOS 26, iOS 26, *)
@Generable
struct FMNutritionFacts: Sendable {
    @Guide(description: "Product or food name if visible on label, otherwise empty")
    let name: String
    @Guide(description: "Serving size text verbatim (e.g. '1 Bar (68g)' or '125 g')")
    let servingSize: String
    @Guide(description: "Calories per serving (kcal). Use 0 if missing.")
    let calories: Int
    @Guide(description: "Protein in grams per serving")
    let proteinG: Double
    @Guide(description: "Total carbohydrate in grams per serving")
    let carbsG: Double
    @Guide(description: "Total fat in grams per serving")
    let fatG: Double
    @Guide(description: "Dietary fiber in grams per serving; 0 if not listed")
    let fiberG: Double
    @Guide(description: "Total sugars in grams per serving; 0 if not listed")
    let sugarG: Double
    @Guide(description: "Sodium in milligrams per serving; 0 if not listed")
    let sodiumMg: Double
}
#endif
