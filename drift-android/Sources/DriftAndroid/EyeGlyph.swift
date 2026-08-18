import SwiftUI

/// Eye glyph drawn as a `Path`: skip-ui's Material map has no eye / visibility
/// / preview entry, so `sym("eye")` fell through to the warning triangle on
/// CoachSharingCard's "See what @coach sees" button — the one control that
/// tells a client exactly what their coach can read (#1233/#1244). A hazard
/// triangle in front of that sentence reads as a privacy alarm, which is the
/// opposite of what the button does.
///
/// Geometry: SF Symbol `eye` on the same 24×24 grid the other drawn glyphs
/// use — an almond rim plus a solid pupil, filled in one pass. The rim is an
/// outer almond wound positive and an inner almond wound negative so it fills
/// as an outline under the default non-zero winding rule (skip-ui has no
/// even-odd fill; same trick as TargetShape's rims).
struct EyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        let center = pt(12, 12)

        var p = Path()
        // Outer almond — left → over the top → right → under → back: additive.
        p.move(to: pt(2, 12))
        p.addQuadCurve(to: pt(22, 12), control: pt(12, 2.2))
        p.addQuadCurve(to: pt(2, 12), control: pt(12, 21.8))
        p.closeSubpath()

        // Inner almond — left → under → right → over: wound the other way, so
        // it punches out and leaves a rim.
        p.move(to: pt(4.2, 12))
        p.addQuadCurve(to: pt(19.8, 12), control: pt(12, 17.8))
        p.addQuadCurve(to: pt(4.2, 12), control: pt(12, 6.2))
        p.closeSubpath()

        // Pupil — solid, so both half-arcs stay positive-wound.
        p.move(to: pt(14.2, 12))
        p.addArc(center: center, radius: 2.2 * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addArc(center: center, radius: 2.2 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        p.closeSubpath()
        return p
    }
}
