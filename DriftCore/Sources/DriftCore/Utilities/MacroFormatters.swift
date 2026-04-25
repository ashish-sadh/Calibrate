import Foundation

/// Display helpers for macro values. Plain `Int(x)` truncates — e.g., 1.5g
/// fiber shown as "1g" and 0.6g fiber shown as "0g" — which confused users
/// logging small-serving fruits ("75g strawberry is 1.5g fiber, why does it
/// say 0?"). #282. We keep integers for bigger values to stay compact in the
/// entry-row macro line, but keep one decimal for sub-10g fiber so small
/// portions don't disappear.
public enum MacroFormatter {
    /// Fiber grams → display string (no unit suffix). One decimal for
    /// non-integer values under 10g, whole number otherwise.
    public static func fiber(_ grams: Double) -> String {
        guard grams > 0 else { return "0" }
        if grams < 10 {
            let rounded = (grams * 10).rounded() / 10
            if rounded == rounded.rounded() {
                return "\(Int(rounded))"
            }
            return String(format: "%.1f", rounded)
        }
        return "\(Int(grams.rounded()))"
    }
}
