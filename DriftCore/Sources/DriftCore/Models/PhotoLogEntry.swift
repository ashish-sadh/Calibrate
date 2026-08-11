import Foundation

// MARK: - Photo Log review model
//
// `PhotoLogServingUnit`, `Confidence` and `PhotoLogItem` all live alongside
// this file in DriftCore. Moved out of the iOS app target 2026-08-11 (#1111):
// the review math — per-gram rates, the #1043 per-unit `originalGrams`, macro
// re-derivation — is identical on both platforms, and Android's Snap review
// needs it verbatim rather than a second implementation that can drift.

/// Mutable editing state for a single `PhotoLogItem` in the review sheet.
/// Users can check/uncheck items, pick a friendlier serving unit, and edit
/// the amount. Calories and macros scale linearly with grams so the summary
/// stays accurate during edits. Separate from `PhotoLogItem` (which is
/// decode-only) so we can keep the wire format immutable. #224 / #267.
/// `Sendable` because every stored property is a value type that already is
/// (`Confidence`, `PhotoLogServingUnit`, String/Double/UUID/[String]). Needed
/// once this crossed into DriftCore: the iOS AI-correction call hands an item
/// to a `@Sendable` async closure across the module boundary.
public struct PhotoLogEditableItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var grams: Double
    public var calories: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var fiberG: Double
    public var confidence: Confidence
    public var selected: Bool
    public var servingUnit: PhotoLogServingUnit
    /// User-visible amount in `servingUnit`. Changing this recomputes `grams`
    /// via `gramsPerServingUnit` and rescales macros.
    public var servingAmount: Double
    /// Ingredient list surfaced from the LLM for plant-points counting. Empty
    /// when the model didn't return it — callers fall back to `name` for
    /// plant classification.
    public var ingredients: [String]
    /// User-initiated edit of a macro field (e.g. "actually this pizza has
    /// 15g protein not 12"). When set, subsequent amount/unit changes still
    /// rescale macros proportionally, but from the user's corrected baseline
    /// rather than the LLM's. Resets the per-gram rates so future reflows
    /// respect the correction.
    public var macrosManuallyEdited: Bool

    /// Per-gram rates — stored as `var` so `setMacros` can update them when
    /// the user hand-corrects one macro. Amount/unit reflows multiply these
    /// by the current grams to keep the row consistent.
    var caloriesPerGram: Double
    var proteinPerGram: Double
    var carbsPerGram: Double
    var fatPerGram: Double
    var fiberPerGram: Double

    /// Per-unit baseline weight for `.pieces` / `.slices` (grams ÷ original count) —
    /// #1043: NOT the plate total, so scaling the count stays proportional.
    let originalGrams: Double

    /// #1044: a blank/unnamed/0-cal row (e.g. an unfilled "Add item") must not be logged
    /// to the diary or written to the searchable food catalog.
    public var isLoggable: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && calories > 0
    }

    public init(from item: PhotoLogItem, id: UUID = UUID()) {
        self.id = id
        self.name = item.name
        self.grams = max(item.grams, 0)
        self.calories = max(item.calories, 0)
        self.proteinG = max(item.proteinG, 0)
        self.carbsG = max(item.carbsG, 0)
        self.fatG = max(item.fatG, 0)
        self.fiberG = max(item.fiberG, 0)
        self.confidence = item.confidence
        self.selected = true
        self.macrosManuallyEdited = false
        if self.grams > 0 {
            self.caloriesPerGram = self.calories / self.grams
            self.proteinPerGram = self.proteinG / self.grams
            self.carbsPerGram = self.carbsG / self.grams
            self.fatPerGram = self.fatG / self.grams
            self.fiberPerGram = self.fiberG / self.grams
        } else {
            self.caloriesPerGram = 0
            self.proteinPerGram = 0
            self.carbsPerGram = 0
            self.fatPerGram = 0
            self.fiberPerGram = 0
        }
        self.ingredients = item.ingredients ?? []

        // Prefer LLM-returned serving_unit + serving_amount. The LLM sees
        // the photo and knows "1.5 slices of pizza" vs "0.75 cup rice" is
        // more natural than the Swift keyword guess. Fall back to the
        // keyword heuristic if the model didn't return anything.
        let resolvedUnit: PhotoLogServingUnit
        let resolvedAmount: Double
        if let aiUnit = PhotoLogServingUnit.parse(item.servingUnit) {
            resolvedUnit = aiUnit
            if let aiAmount = item.servingAmount, aiAmount > 0 {
                resolvedAmount = aiAmount
            } else if let gpu = aiUnit.fixedGramsPerUnit, gpu > 0 {
                resolvedAmount = self.grams / gpu
            } else {
                resolvedAmount = self.grams > 0 ? 1 : 0
            }
        } else {
            let suggested = PhotoLogServingUnit.suggested(forName: item.name)
            resolvedUnit = suggested
            if let gpu = suggested.fixedGramsPerUnit {
                resolvedAmount = gpu > 0 ? self.grams / gpu : 0
            } else {
                resolvedAmount = self.grams > 0 ? 1 : 0
            }
        }
        self.servingUnit = resolvedUnit
        self.servingAmount = resolvedAmount
        // #1043: for count units (pieces/slices) the LLM's `grams` is the PLATE TOTAL and
        // `serving_amount` is the COUNT, so one unit weighs grams / count — not the whole
        // plate. Store the per-unit weight so `grams == servingAmount × gramsPerServingUnit`
        // holds and nudging the count (3→4 idli) scales by ~50 g, not 150 g.
        if resolvedUnit.fixedGramsPerUnit == nil, resolvedAmount > 0 {
            self.originalGrams = self.grams / resolvedAmount
        } else {
            self.originalGrams = self.grams
        }
    }

    /// Grams per 1 unit of the currently-selected serving unit.
    /// `fixedGramsPerUnit` handles weight/volume conversions; pieces/slices
    /// use the LLM's `originalGrams` as the per-unit weight.
    public var gramsPerServingUnit: Double {
        if let gpu = servingUnit.fixedGramsPerUnit { return gpu }
        // pieces / slices: one unit = the LLM's original weight for this food.
        return originalGrams > 0 ? originalGrams : 100
    }

    /// Update `servingAmount` and reflow `grams` + macros.
    public mutating func setAmount(_ newAmount: Double) {
        servingAmount = max(newAmount, 0)
        grams = servingAmount * gramsPerServingUnit
        rescale()
    }

    /// Switch the displayed serving unit, keeping the current grams the same.
    /// `servingAmount` is recomputed so the user's macros don't jump when
    /// they change from "180 g" to "oz" (they see "6.4 oz" instead).
    public mutating func setUnit(_ newUnit: PhotoLogServingUnit) {
        servingUnit = newUnit
        let gpu = gramsPerServingUnit
        servingAmount = gpu > 0 ? grams / gpu : 0
    }

    /// Re-derive calories+macros after `grams` is edited. Callers mutate
    /// `grams` then invoke this to keep the per-row totals consistent.
    mutating func rescale() {
        let g = max(grams, 0)
        grams = g
        calories = caloriesPerGram * g
        proteinG = proteinPerGram * g
        carbsG = carbsPerGram * g
        fatG = fatPerGram * g
        fiberG = fiberPerGram * g
    }

    /// Apply a user-entered macro value at the current grams. Re-derives the
    /// per-gram rate so a later amount change reflows proportionally from
    /// the corrected baseline. Example: user sets protein 12→15 for their
    /// 120 g pizza slice → `proteinPerGram` becomes 0.125 so a 1→2 slice
    /// change now gives 30 g protein, not the original 24.
    public mutating func setMacro(_ field: MacroField, to value: Double) {
        let v = max(value, 0)
        let g = max(grams, 0)
        switch field {
        case .calories:
            calories = v
            caloriesPerGram = g > 0 ? v / g : 0
        case .protein:
            proteinG = v
            proteinPerGram = g > 0 ? v / g : 0
        case .carbs:
            carbsG = v
            carbsPerGram = g > 0 ? v / g : 0
        case .fat:
            fatG = v
            fatPerGram = g > 0 ? v / g : 0
        case .fiber:
            fiberG = v
            fiberPerGram = g > 0 ? v / g : 0
        }
        macrosManuallyEdited = true
    }

    public enum MacroField {
        case calories, protein, carbs, fat, fiber
    }

    /// Apply an AI correction to this single item. Replaces name, grams,
    /// macros, and ingredients with the AI's updated values. `selected` is
    /// intentionally preserved — the checkbox is the user's choice, not a
    /// correctness signal. `macrosManuallyEdited` is reset since AI just
    /// replaced the baseline. Uses fixed-conversion units only (not pieces/
    /// slices) to avoid stale `originalGrams` after the swap.
    public mutating func applyAICorrection(_ aiItem: PhotoLogItem) {
        name = aiItem.name
        let g = max(aiItem.grams, 1)
        let c = max(aiItem.calories, 0)
        let p = max(aiItem.proteinG, 0)
        let carb = max(aiItem.carbsG, 0)
        let f = max(aiItem.fatG, 0)
        let fb = max(aiItem.fiberG, 0)
        grams = g
        calories = c
        proteinG = p
        carbsG = carb
        fatG = f
        fiberG = fb
        caloriesPerGram = c / g
        proteinPerGram  = p / g
        carbsPerGram    = carb / g
        fatPerGram      = f / g
        fiberPerGram    = fb / g
        // Crash-audit: was `aiUnit.fixedGramsPerUnit != nil` + `!`
        // unwrap. The cleaner double-bind avoids the bang.
        if let aiUnit = PhotoLogServingUnit.parse(aiItem.servingUnit),
           let gpu = aiUnit.fixedGramsPerUnit {
            servingUnit = aiUnit
            servingAmount = gpu > 0 ? g / gpu : 1
        } else {
            servingUnit = .grams
            servingAmount = g
        }
        if let ing = aiItem.ingredients { ingredients = ing }
        confidence = aiItem.confidence
        macrosManuallyEdited = false
        // `selected` intentionally preserved — do not touch
    }

    /// Apply a DB food match from a user correction hint.
    /// Substitutes the canonical name, recalculates per-gram rates from the
    /// DB food's macros, and rescales to the current grams. If grams is 0,
    /// a category-aware portion default is applied first.
    public mutating func applyHintMatch(_ food: Food) {
        name = food.name
        if grams < 1 {
            grams = PhotoLogMatcher.portionDefault(category: food.category, recognizedName: food.name)
        }
        let g = food.servingSize > 0 ? food.servingSize : grams
        caloriesPerGram = food.calories / g
        proteinPerGram  = food.proteinG / g
        carbsPerGram    = food.carbsG / g
        fatPerGram      = food.fatG / g
        fiberPerGram    = food.fiberG / g
        calories = caloriesPerGram * grams
        proteinG = proteinPerGram * grams
        carbsG   = carbsPerGram * grams
        fatG     = fatPerGram * grams
        fiberG   = fiberPerGram * grams
        confidence = .high
        macrosManuallyEdited = false
    }

    /// Empty item the user creates when they tap "Add item" in the review
    /// sheet — the model missed something and they want to fill it in by
    /// hand. Defaults to 100 g / zero macros; per-gram rates stay at zero
    /// until a macro is typed so `rescale()` doesn't wipe the user's input
    /// when they adjust the amount.
    public static func blank() -> PhotoLogEditableItem {
        let seed = PhotoLogItem(
            name: "",
            grams: 100,
            calories: 0,
            proteinG: 0,
            carbsG: 0,
            fatG: 0,
            fiberG: 0,
            confidence: .medium,
            servingUnit: "grams",
            servingAmount: 100,
            ingredients: nil
        )
        return PhotoLogEditableItem(from: seed)
    }
}

/// Summed macro totals across the currently-selected items. Pure helper so
/// the review view can re-render on check/uncheck without re-running UI code.
public struct PhotoLogTotals: Equatable {
    public var calories: Int
    public var proteinG: Int
    public var carbsG: Int
    public var fatG: Int
    public var selectedCount: Int

    public static let zero = PhotoLogTotals(calories: 0, proteinG: 0, carbsG: 0, fatG: 0, selectedCount: 0)

    public static func sum(_ items: [PhotoLogEditableItem]) -> PhotoLogTotals {
        var totals = PhotoLogTotals.zero
        for item in items where item.selected {
            totals.calories += item.calories.rounded().safeInt  // #1036: editable macros can be huge
            totals.proteinG += item.proteinG.rounded().safeInt
            totals.carbsG += item.carbsG.rounded().safeInt
            totals.fatG += item.fatG.rounded().safeInt
            totals.selectedCount += 1
        }
        return totals
    }
}
