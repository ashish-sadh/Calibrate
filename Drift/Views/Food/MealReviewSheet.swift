import SwiftUI
import DriftCore

/// Standalone, presentable wrapper around the Photo Log review screen so ANY
/// source — text/voice food logging, "log my usual lunch" — can reuse the SAME
/// editable meal sheet that Snap uses: review items, tweak amount/macros, drop
/// what you didn't have, then log. Seeds `PhotoLogReviewView` with plain
/// `PhotoLogItem`s (no photo). #food-logging-reuse
struct MealReviewSheet: View {
    @State private var items: [PhotoLogEditableItem]
    private let confidence: Confidence
    private let notes: String?
    private let foodLog: FoodLogViewModel
    private let onLogged: () -> Void

    init(items: [PhotoLogItem],
         confidence: Confidence = .medium,
         notes: String? = nil,
         foodLog: FoodLogViewModel,
         onLogged: @escaping () -> Void) {
        _items = State(initialValue: items.map { PhotoLogEditableItem(from: $0) })
        self.confidence = confidence
        self.notes = notes
        self.foodLog = foodLog
        self.onLogged = onLogged
    }

    var body: some View {
        PhotoLogReviewView(
            items: $items,
            overallConfidence: confidence,
            notes: notes,
            photo: nil,            // no photo: per-item AI-correction row hides itself
            foodLog: foodLog,
            onLogged: onLogged,
            onRetake: {}           // nothing to retake on a text/voice meal
        )
    }
}
