import Foundation

extension WorkoutSet {
    /// Set summary in the user's weight unit. Storage is always lbs
    /// (`weightLbs`), so the unit is a render-time concern.
    ///
    /// The unit is a REQUIRED parameter, deliberately. This used to be
    /// `var display` with " lbs" hardcoded, and every history surface
    /// inherited that — kg users logged 60 kg and read it back as
    /// "132.3 lbs" (#1085). A defaulted parameter would let the next call
    /// site silently keep lbs the same way, so adding one has to be a
    /// decision about units.
    public func display(in unit: WeightUnit) -> String {
        if let d = durationSec, d > 0 {
            let m = d / 60; let s = d % 60
            let timeStr = m > 0 ? "\(m):\(String(format: "%02d", s))" : "\(s)s"
            let w = weightLbs.map { "\(unit.entryText(fromLbs: $0)) \(unit.displayName) · " } ?? ""
            return "\(w)\(timeStr)"
        }
        let w = weightLbs.map { "\(unit.entryText(fromLbs: $0)) \(unit.displayName)" } ?? "BW"
        let r = reps.map { "× \($0)" } ?? ""
        return "\(w) \(r)"
    }
}
