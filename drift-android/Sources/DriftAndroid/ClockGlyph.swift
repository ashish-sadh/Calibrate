import SwiftUI

/// Clock glyph drawn as a `Path`: skip-ui's Material map has no clock icon,
/// so `sym("clock")` shipped a calendar stand-in — which sat NEXT TO the real
/// calendar glyph in the active-workout header and read as two dates
/// (#1074 residual 2). Workout surfaces draw the real face instead.
///
/// Geometry: Google Material Symbols "schedule" (Apache License 2.0, ©
/// Google LLC — see Docs/licenses.md), hand-converted from its 24×24 SVG
/// path. The dial is two opposite-wound rims (half-arcs, since a single
/// 360° sweep collapses to 0° mod 360 in android.graphics.Path.arcTo) so
/// the ring fills under the default non-zero winding rule — skip-ui has no
/// even-odd fill.
struct ClockFaceShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        let center = pt(12, 12)
        var p = Path()
        // Dial: outer rim sweeps positive, inner rim negative → annulus.
        p.move(to: pt(22, 12))
        p.addArc(center: center, radius: 10 * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addArc(center: center, radius: 10 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        p.closeSubpath()
        p.move(to: pt(20, 12))
        p.addArc(center: center, radius: 8 * s, startAngle: .degrees(360), endAngle: .degrees(180), clockwise: true)
        p.addArc(center: center, radius: 8 * s, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        p.closeSubpath()
        // Hands: minute up to 12, hour toward ~4.
        p.move(to: pt(12.5, 7))
        p.addLine(to: pt(11, 7))
        p.addLine(to: pt(11, 13))
        p.addLine(to: pt(16.25, 16.15))
        p.addLine(to: pt(17, 14.92))
        p.addLine(to: pt(12.5, 12.25))
        p.closeSubpath()
        return p
    }
}
