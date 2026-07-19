import SwiftUI

// Small shims for SwiftUI API that SkipFuseUI doesn't cover yet, so the
// Theme/view code copied from iOS compiles unchanged on Android.
#if os(Android)
extension Font {
    /// SkipUI has no tabular-figures variant — identity on Android.
    func monospacedDigit() -> Font { self }
}
#endif
