import SwiftUI

/// Target/bullseye glyph drawn as a `Path`: skip-ui's Material map has no
/// "target", so `sym("target")` fell back to `house` — the TODAY TAB ICON, the
/// most-seen glyph in the app, rendered a house while iPhone shows concentric
/// rings (`Drift/ContentView.swift:261`). Same failure class as the
/// shopping-cart food icon and the bullet-list dumbbell (operator, directive
/// 0a: "a missing mapping means find the closest same-meaning icon, not a
/// different object").
///
/// Geometry: SF Symbol "target" — two rims plus a center dot, on the same
/// 24×24 grid the other drawn glyphs use. Each rim is two opposite-wound
/// half-arcs so it fills as an annulus under the default non-zero winding
/// rule; skip-ui has no even-odd fill, and a single 360° sweep collapses to
/// 0° mod 360 in android.graphics.Path.arcTo (see ClockFaceShape).
struct TargetShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        let center = pt(12, 12)
        var p = Path()

        /// One annulus: outer rim wound positive, inner rim negative so it
        /// punches back out and leaves a stroke-width ring.
        func rim(outer: Double, inner: Double) {
            p.move(to: pt(12 + outer, 12))
            p.addArc(center: center, radius: outer * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.addArc(center: center, radius: outer * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            p.closeSubpath()
            p.move(to: pt(12 + inner, 12))
            p.addArc(center: center, radius: inner * s, startAngle: .degrees(360), endAngle: .degrees(180), clockwise: true)
            p.addArc(center: center, radius: inner * s, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            p.closeSubpath()
        }

        rim(outer: 10.0, inner: 8.4)
        rim(outer: 6.2, inner: 4.6)

        // Center dot — solid, so both half-arcs stay positive-wound.
        p.move(to: pt(14.4, 12))
        p.addArc(center: center, radius: 2.4 * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addArc(center: center, radius: 2.4 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        p.closeSubpath()
        return p
    }
}
