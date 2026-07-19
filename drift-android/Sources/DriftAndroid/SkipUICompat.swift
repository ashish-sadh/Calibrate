import SwiftUI

// Small shims for SwiftUI API that SkipFuseUI doesn't cover yet, so the
// Theme/view code copied from iOS compiles unchanged on Android.
#if os(Android)
extension Font {
    /// SkipUI has no tabular-figures variant — identity on Android.
    func monospacedDigit() -> Font { self }
}

extension View {
    /// SkipUI has no contentShape — the tap target is just the view's own
    /// frame on Android (slightly smaller hit area, no visual difference).
    func contentShape(_ shape: some Shape) -> some View { self }

    /// skip-fuse-ui marks safeAreaInset unavailable; stacking the bar under
    /// the content reproduces the iOS visual (fixed bottom bar, scroll
    /// viewport shrinks). Available overload wins resolution over the
    /// unavailable SkipSwiftUI one.
    func safeAreaInset(edge: VerticalEdge, spacing: CGFloat? = nil,
                       @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: spacing ?? 0) {
            self
            content()
        }
    }
}
#endif
