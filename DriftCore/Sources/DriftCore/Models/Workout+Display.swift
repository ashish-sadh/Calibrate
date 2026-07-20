import Foundation

extension WorkoutSet {
    public var display: String {
        if let d = durationSec, d > 0 {
            let m = d / 60; let s = d % 60
            let timeStr = m > 0 ? "\(m):\(String(format: "%02d", s))" : "\(s)s"
            let w = weightLbs.map { "\(WeightFormatter.plain($0)) lbs · " } ?? ""
            return "\(w)\(timeStr)"
        }
        let w = weightLbs.map { "\(WeightFormatter.plain($0)) lbs" } ?? "BW"
        let r = reps.map { "× \($0)" } ?? ""
        return "\(w) \(r)"
    }
}
