import Foundation
import DriftCore

// MARK: - Serving unit (Photo Log specific)
//
// `PhotoLogServingUnit` lives in DriftCore (pure data + parse/suggest helpers).
// The remainder of this file — PhotoLogEditableItem, PhotoLogViewState,
// PhotoLogTotals — references CloudVision types (Confidence, PhotoLogItem)
// and stays in the iOS app target.

/// Mutable editing state for a single `PhotoLogItem` in the review sheet.
/// Users can check/uncheck items, pick a friendlier serving unit, and edit
/// the amount. Calories and macros scale linearly with grams so the summary
/// stays accurate during edits. Separate from `PhotoLogItem` (which is
/// decode-only) so we can keep the wire format immutable. #224 / #267.
struct PhotoLogEditableItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var grams: Double
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var confidence: Confidence
    var selected: Bool
    var servingUnit: PhotoLogServingUnit
    /// User-visible amount in `servingUnit`. Changing this recomputes `grams`
    /// via `gramsPerServingUnit` and rescales macros.
    var servingAmount: Double
    /// Ingredient list surfaced from the LLM for plant-points counting. Empty
    /// when the model didn't return it — callers fall back to `name` for
    /// plant classification.
    var ingredients: [String]
    /// User-initiated edit of a macro field (e.g. "actually this pizza has
    /// 15g protein not 12"). When set, subsequent amount/unit changes still
    /// rescale macros proportionally, but from the user's corrected baseline
    /// rather than the LLM's. Resets the per-gram rates so future reflows
    /// respect the correction.
    var macrosManuallyEdited: Bool

    /// Per-gram rates — stored as `var` so `setMacros` can update them when
    /// the user hand-corrects one macro. Amount/unit reflows multiply these
    /// by the current grams to keep the row consistent.
    var caloriesPerGram: Double
    var proteinPerGram: Double
    var carbsPerGram: Double
    var fatPerGram: Double
    var fiberPerGram: Double

    /// LLM's original grams for this food — used as the 1-piece / 1-slice
    /// baseline weight when the user picks `.pieces` or `.slices`.
    let originalGrams: Double

    init(from item: PhotoLogItem, id: UUID = UUID()) {
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
        self.originalGrams = self.grams
        self.ingredients = item.ingredients ?? []

        // Prefer LLM-returned serving_unit + serving_amount. The LLM sees
        // the photo and knows "1.5 slices of pizza" vs "0.75 cup rice" is
        // more natural than the Swift keyword guess. Fall back to the
        // keyword heuristic if the model didn't return anything.
        if let aiUnit = PhotoLogServingUnit.parse(item.servingUnit) {
            self.servingUnit = aiUnit
            if let aiAmount = item.servingAmount, aiAmount > 0 {
                self.servingAmount = aiAmount
            } else if let gpu = aiUnit.fixedGramsPerUnit, gpu > 0 {
                self.servingAmount = self.grams / gpu
            } else {
                self.servingAmount = self.originalGrams > 0 ? 1 : 0
            }
        } else {
            let suggested = PhotoLogServingUnit.suggested(forName: item.name)
            self.servingUnit = suggested
            if let gpu = suggested.fixedGramsPerUnit {
                self.servingAmount = gpu > 0 ? self.grams / gpu : 0
            } else {
                self.servingAmount = self.originalGrams > 0 ? 1 : 0
            }
        }
    }

    /// Grams per 1 unit of the currently-selected serving unit.
    /// `fixedGramsPerUnit` handles weight/volume conversions; pieces/slices
    /// use the LLM's `originalGrams` as the per-unit weight.
    var gramsPerServingUnit: Double {
        if let gpu = servingUnit.fixedGramsPerUnit { return gpu }
        // pieces / slices: one unit = the LLM's original weight for this food.
        return originalGrams > 0 ? originalGrams : 100
    }

    /// Update `servingAmount` and reflow `grams` + macros.
    mutating func setAmount(_ newAmount: Double) {
        servingAmount = max(newAmount, 0)
        grams = servingAmount * gramsPerServingUnit
        rescale()
    }

    /// Switch the displayed serving unit, keeping the current grams the same.
    /// `servingAmount` is recomputed so the user's macros don't jump when
    /// they change from "180 g" to "oz" (they see "6.4 oz" instead).
    mutating func setUnit(_ newUnit: PhotoLogServingUnit) {
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
    mutating func setMacro(_ field: MacroField, to value: Double) {
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

    enum MacroField {
        case calories, protein, carbs, fat, fiber
    }

    /// Empty item the user creates when they tap "Add item" in the review
    /// sheet — the model missed something and they want to fill it in by
    /// hand. Defaults to 100 g / zero macros; per-gram rates stay at zero
    /// until a macro is typed so `rescale()` doesn't wipe the user's input
    /// when they adjust the amount.
    static func blank() -> PhotoLogEditableItem {
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

/// UI phases of the Photo Log flow. A single `@State` holds this so the
/// capture/review sheet can swap layouts without nested sheets. #224 / #267.
enum PhotoLogViewState: Equatable {
    case capture                            // pick photo OR take one
    case analyzing                          // in-flight API call
    case review([PhotoLogEditableItem], Confidence, String?)  // items, overall, notes
    case empty                              // 0 items returned
    case error(String)                      // user-visible message
}

/// Summed macro totals across the currently-selected items. Pure helper so
/// the review view can re-render on check/uncheck without re-running UI code.
struct PhotoLogTotals: Equatable {
    var calories: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var selectedCount: Int

    static let zero = PhotoLogTotals(calories: 0, proteinG: 0, carbsG: 0, fatG: 0, selectedCount: 0)

    static func sum(_ items: [PhotoLogEditableItem]) -> PhotoLogTotals {
        var totals = PhotoLogTotals.zero
        for item in items where item.selected {
            totals.calories += Int(item.calories.rounded())
            totals.proteinG += Int(item.proteinG.rounded())
            totals.carbsG += Int(item.carbsG.rounded())
            totals.fatG += Int(item.fatG.rounded())
            totals.selectedCount += 1
        }
        return totals
    }
}
