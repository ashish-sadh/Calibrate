import Foundation

/// Soft typo guard for numbers typed into a set row. Returns a gentle
/// confirmation line when an entry looks like a fat-finger — the classic
/// extra-digit slip (98 → 980) — and `nil` otherwise.
///
/// Deliberately conservative: it must almost never fire on a real set, or
/// people learn to dismiss it blind and it stops catching anything. So it only
/// speaks up on absolute impossibilities or a large jump past the last session.
public enum SetEntrySanity {

    /// Absolute ceilings — above these it is essentially always a typo. The
    /// heaviest hand-logged barbell lifts sit far under 1500 lb; a single set
    /// past 100 reps or a 90-minute hold don't happen.
    static let maxPlausibleWeightLbs = 1500.0
    static let maxPlausibleReps = 100
    static let maxPlausibleDurationSec = 5400  // 90 min

    /// A committed weight that leaps to more than 3× the last top set AND is at
    /// least 100 lb heavier is the signature of an extra digit (98 → 980). The
    /// 100 lb floor keeps light accessory work (5 → 15 lb) from ever tripping it.
    static let jumpMultiple = 3.0
    static let jumpFloorLbs = 100.0

    /// A soft "are you sure?" line, or `nil` when the numbers look fine.
    /// - weightLbs: the entered weight already converted to storage lbs (`nil` if blank).
    /// - reps: the entered rep count, or seconds when `isDuration`.
    /// - previousTopWeightLbs: last session's top working weight in lbs, if known.
    /// - unit: the user's display unit, so the message reads in their numbers.
    public static func warning(weightLbs: Double?,
                               reps: Int?,
                               isDuration: Bool,
                               previousTopWeightLbs: Double?,
                               unit: WeightUnit) -> String? {
        if let w = weightLbs, w > 0 {
            let shown = "\(WeightFormatter.plain(unit.convertFromLbs(w)))\(unit.displayName)"
            if w > maxPlausibleWeightLbs {
                return "Whoa — \(shown) is really heavy. Sure that's right?"
            }
            if let prev = previousTopWeightLbs, prev > 0,
               w > prev * jumpMultiple, w - prev >= jumpFloorLbs {
                return "Whoa — \(shown) is a big jump from last time. Sure that's right?"
            }
        }
        if isDuration {
            if let s = reps, s > maxPlausibleDurationSec {
                return "Whoa — that's over 90 min for one set. Sure that's right?"
            }
        } else if let r = reps, r > maxPlausibleReps {
            return "Whoa — \(r) reps is a lot. Sure that's right?"
        }
        return nil
    }
}
