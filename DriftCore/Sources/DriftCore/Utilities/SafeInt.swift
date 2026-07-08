import Foundation

public extension Double {
    /// #1036: `Int(self)` is an uncatchable trap on NaN, ±∞, and any value outside Int64
    /// range (~9.2e18). Clamp instead — safe for display and totals fed by unvalidated
    /// input (remote model JSON, pasted/typed numbers, corrupt imports).
    var safeInt: Int {
        if isNaN { return 0 }
        if self >= Double(Int.max) { return Int.max }
        if self <= Double(Int.min) { return Int.min }
        return Int(self)
    }
}
