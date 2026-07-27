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

    /// iOS 26 draws a system glass PILL behind toolbar text buttons — Drift's
    /// source is a bare `Button("Close")` (scout "workout-chrome" finding #1,
    /// #1064 ledger); the chrome is painted by the OS, not by our code. Ported
    /// in-content headers (#1089 pattern: SkipUI wastes an ~80dp band on a
    /// real nav bar inside a sheet) need to draw that chrome explicitly or
    /// every such sheet reads as chrome-less next to iOS.
    func toolbarPillChrome() -> some View {
        foregroundStyle(.primary)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Theme.pillBackground, in: Capsule())
    }

    /// Same system chrome, icon-button variant — iOS draws a soft-shadowed
    /// near-white circle behind toolbar icon-only buttons (e.g. the in-workout
    /// X), distinctly brighter than the gray text pill above. Icons already
    /// set their own foregroundStyle, so this only adds the background. Real
    /// `.shadow()` is Android-banned here (#1074: skip-ui re-composes +
    /// gaussian-blurs the shadow every frame) — a single offset fill at low
    /// opacity reads as the same soft lift at icon-button size.
    func toolbarCircleChrome() -> some View {
        padding(8)
            .background(
                ZStack {
                    Circle().fill(Color.black.opacity(0.06)).offset(y: 1.5)
                    Circle().fill(Theme.cardBackgroundElevated)
                }
            )
    }
}
#endif
