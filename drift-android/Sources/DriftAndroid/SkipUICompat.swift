import SwiftUI

// Small shims for SwiftUI API that SkipFuseUI doesn't cover yet, so the
// Theme/view code copied from iOS compiles unchanged on Android.
#if os(Android)
extension Font {
    /// SkipUI has no tabular-figures variant — identity on Android.
    func monospacedDigit() -> Font { self }
}

extension View {
    /// skip-fuse-ui has no contentShape at all, so an identity shim collapses the
    /// tap target to the *drawn* pixels — for a `Text … Spacer() … Text` row that
    /// means the whitespace between them is untappable. iOS hit exactly this and
    /// it was field-reported as history rows being "very hard to click"
    /// (2026-07-10); Android shipped the reported bug until now.
    /// A near-transparent fill IS a drawn surface, so Compose's pointer input
    /// covers the whole frame. Visually identical at alpha 0.0001.
    func contentShape(_ shape: some Shape) -> some View {
        background(shape.fill(Color.white.opacity(0.0001)))
    }

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
