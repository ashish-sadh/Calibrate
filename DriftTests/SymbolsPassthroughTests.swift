import Testing
@testable import Drift

/// sym() substitutes Material-safe glyphs ONLY on Android — on Darwin it must
/// be a strict passthrough, or iOS silently trades its SF Symbols for the
/// Android fallbacks. Locks the Darwin branch of SharedUI/Symbols.swift (the
/// Android branch is exercised by the emulator aesthetic gate, which iOS
/// simulator tests cannot reach). Tier 1 (sym is app-target internal).
struct SymbolsPassthroughTests {

    @Test func symIsIdentityOnDarwin() {
        let names = [
            "star", "star.fill", "star.slash",
            "figure.strengthtraining.traditional", "figure.run", "figure.core.training",
            "clock", "trophy.fill", "play.circle.fill", "chart.bar",
            "wrench.and.screwdriver", "link", "circle.dotted",
            // #1233 glyph sweep — every name whose Android mapping changed, so
            // a future map line can't reach back across the #if and swap the
            // iPhone's real symbol for the Android stand-in.
            "exclamationmark.bubble", "exclamationmark.bubble.fill",
            "exclamationmark.circle", "exclamationmark.circle.fill",
            "exclamationmark.triangle", "exclamationmark.triangle.fill",
            "person.badge.plus", "message.fill", "bubble.left.fill",
            "bubble.left.and.bubble.right.fill", "quote.bubble",
            "arrow.up.circle.fill", "chart.bar.fill",
            "eye", "target", "hourglass",
            "camera", "camera.fill", "doc.viewfinder",
            "not.a.real.symbol",
        ]
        for name in names {
            #expect(sym(name) == name, "sym must not rewrite '\(name)' on Darwin")
        }
    }
}
