import Foundation

/// Display helpers for lifted weights. Plain `Int(x)` truncates, which cost us
/// real data: a set stored at 137.5 lbs rendered as "137 lbs", and the Edit Set
/// field prefilled "137", so a user tapping in to fix a *rep* count silently
/// wrote the weight back down half a pound (#1080). Fractional weights are
/// routine — 2.5 lb plate jumps, and every kg entry converted to lbs.
///
/// Whole numbers stay whole so the common case renders exactly as before; one
/// decimal otherwise.
public enum WeightFormatter {
    /// Weight → display string, no unit suffix: `137`, `137.5`.
    ///
    /// Rounds to one decimal *before* testing for a whole number, so a value
    /// like 137.04 reads "137" rather than "137.0".
    public static func plain(_ weight: Double) -> String {
        guard weight.isFinite else { return "0" }
        let rounded = (weight * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(rounded.safeInt)" }
        return String(format: "%.1f", rounded)
    }
}
