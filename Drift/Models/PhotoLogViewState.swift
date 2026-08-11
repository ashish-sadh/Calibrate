import Foundation
import DriftCore

/// UI phases of the Photo Log flow. A single `@State` holds this so the
/// capture/review sheet can swap layouts without nested sheets. #224 / #267.
///
/// iOS-only: it describes `PhotoLogFlowView`'s screen sequence, not the review
/// math. Android's Snap sheet has its own phase enum (no `.empty` — it routes a
/// food-free photo to its own message), so this stayed out of DriftCore when
/// `PhotoLogEditableItem` moved there (#1111).
enum PhotoLogViewState: Equatable {
    case capture                            // pick photo OR take one
    case analyzing                          // in-flight API call
    case review([PhotoLogEditableItem], Confidence, String?)  // items, overall, notes
    case empty                              // 0 items returned
    case error(String)                      // user-visible message
}
