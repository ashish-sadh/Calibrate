import SwiftUI

/// Send glyph drawn as a `Path`: skip-ui's Material map has no arrow-circle of
/// any kind (checked `composeSymbolName` in the pinned 1.58.0 — zero arrow
/// entries beyond the four bare directions), so `sym("arrow.up.circle.fill")`
/// returned `paperplane.fill` and the COACH SEND BUTTON — the showstopper
/// surface — rendered a paper plane where the iPhone renders a filled circle
/// with an up arrow (#1210). The plane keeps the meaning and loses the object,
/// which is exactly the substitution directive 0a bans.
///
/// Geometry: SF Symbol `arrow.up.circle.fill` on the same 24×24 grid the other
/// drawn glyphs use — a solid disc with the arrow KNOCKED OUT, so a single
/// `.fill(tint)` reproduces iOS's two-tone look without the call site needing
/// to know its own background colour. The disc is two positive-wound half-arcs
/// (a single 360° sweep collapses to 0° mod 360 in android.graphics.Path.arcTo
/// — see ClockFaceShape) and the arrow is traversed the opposite way round, so
/// it punches back out under the default non-zero winding rule; skip-ui has no
/// even-odd fill.
struct SendUpShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        let center = pt(12, 12)

        var p = Path()
        // Disc — right → bottom → left → top, the additive direction.
        p.move(to: pt(22, 12))
        p.addArc(center: center, radius: 10 * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addArc(center: center, radius: 10 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        p.closeSubpath()

        // Arrow — apex → left arm → stem → right arm, i.e. wound against the
        // disc above, so this region reads as a hole rather than more ink.
        //
        // CONSTANT-THICKNESS arms with round caps, not a solid wedge: SF
        // Symbols draws a stroked chevron with a rounded apex, rounded barb
        // ends and a rounded stem foot, and a wedge reads chunky beside it.
        //
        // Every number is MEASURED off the iPhone render rather than guessed —
        // the send disc was screenshotted on both devices at the same state and
        // the white hole measured in pixels, normalised to this 24-grid (where
        // the disc spans 2…22). iPhone: arrow top 6.9, foot 16.8, head width
        // 8.0, arm thickness 1.6. Eyeballing it got the thickness 70% too fat
        // and the whole arrow 11% too tall, which is exactly what read as
        // "chunky" in the first side-by-side.
        let t = 0.8 * s               // half the arm thickness
        let capL = pt(8.8, 11.23)     // centre of the left barb's round cap
        let capR = pt(15.2, 11.23)    // …and the right
        let foot = pt(12, 16.0)       // centre of the stem's round foot

        p.move(to: pt(11.2, 7.698))   // on the left arm's outer edge
        p.addLine(to: pt(8.234, 10.664))
        p.addArc(center: capL, radius: t, startAngle: .degrees(225), endAngle: .degrees(45), clockwise: true)
        p.addLine(to: pt(11.2, 9.962))   // armpit, where the arm meets the stem
        p.addLine(to: pt(11.2, 16.0))
        p.addArc(center: foot, radius: t, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: pt(12.8, 9.962))
        p.addLine(to: pt(14.634, 11.796))
        p.addArc(center: capR, radius: t, startAngle: .degrees(135), endAngle: .degrees(-45), clockwise: true)
        p.addLine(to: pt(12.8, 7.698))
        // Rounded apex. The control sits ABOVE the point where the two outer
        // edges would meet (12, 6.9) so the curve PEAKS there — put the control
        // on the meeting point itself and the quad cuts the corner off short.
        p.addQuadCurve(to: pt(11.2, 7.698), control: pt(12, 6.10))
        p.closeSubpath()
        return p
    }
}
