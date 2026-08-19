import SwiftUI

/// Globe glyph drawn as a `Path`: the pinned skip-ui 1.58.0 (#1134) maps NO
/// globe, cloud or wifi symbol of any kind (Symbols.swift records the same
/// fact for the Photo Log cloud banner), so `Leaderboard.Visibility.everyone`
/// — whose SF name is `globe` — was the one visibility chip of three rendering
/// the WARNING TRIANGLE while "Private" and "Friends" showed real glyphs
/// (#1248). Directive 0a: a missing mapping means the closest same-meaning
/// icon, never a different object — and there is no mapped audience glyph to
/// borrow, so the object is drawn. Same recipe as
/// `TargetGlyph`/`ClockGlyph`/`FoodGlyph`.
///
/// Geometry: Google Material Symbols "public" (Apache License 2.0, © Google
/// LLC — see Docs/licenses.md), reduced to the three strokes that still read
/// as a globe at a 9pt chip: the rim, the equator and one meridian. Stroked,
/// not filled — call sites pass the chip's own tint so the selected and
/// unselected capsules keep their colours.
///
/// The rim is two 180° half-arcs because a single 360° sweep collapses to
/// 0° mod 360 in `android.graphics.Path.arcTo` (see ClockFaceShape).
struct GlobeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        let center = pt(12, 12)
        var p = Path()

        // Rim.
        p.move(to: pt(23, 12))
        p.addArc(center: center, radius: 11 * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addArc(center: center, radius: 11 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)

        // Equator.
        p.move(to: pt(1, 12))
        p.addLine(to: pt(23, 12))

        // Meridian: a narrow vertical ellipse inscribed in the rim.
        p.addEllipse(in: CGRect(x: pt(6.5, 1).x, y: pt(6.5, 1).y,
                                width: 11 * s, height: 22 * s))
        return p
    }
}
