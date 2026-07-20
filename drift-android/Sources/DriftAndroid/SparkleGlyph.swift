import SwiftUI

/// Sparkle glyph drawn as a `Path`: skip-ui's Material map has no sparkle of any
/// kind (grepped — no `AutoAwesome` entry), so `sym("sparkles")` fell back to
/// `star.fill`. A solid STAR in front of "what's next · form tips · ask
/// anything" reads as *favourite* or *rate this*, not as the AI affordance it
/// is — the same directive-0a "different object" failure as the shopping-cart
/// food icon, the bullet-list dumbbell and the star-for-flame.
///
/// Two four-pointed stars, large upper-left plus small lower-right, matching how
/// SF Symbols composes `sparkles`. The concave sides come from quadratic
/// controls pulled toward each star's own centre — that concavity is what
/// separates a sparkle from a plain star, so it is the one property worth
/// getting right.
struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        /// One four-pointed star: cardinal points at `radius`, sides bowed in
        /// toward the centre by `waist`.
        func star(_ p: inout Path, cx: Double, cy: Double, radius: Double, waist: Double) {
            p.move(to: pt(cx, cy - radius))
            p.addQuadCurve(to: pt(cx + radius, cy), control: pt(cx + waist, cy - waist))
            p.addQuadCurve(to: pt(cx, cy + radius), control: pt(cx + waist, cy + waist))
            p.addQuadCurve(to: pt(cx - radius, cy), control: pt(cx - waist, cy + waist))
            p.addQuadCurve(to: pt(cx, cy - radius), control: pt(cx - waist, cy - waist))
            p.closeSubpath()
        }

        var p = Path()
        star(&p, cx: 9.5, cy: 9.5, radius: 7.5, waist: 2.1)
        star(&p, cx: 18.0, cy: 18.0, radius: 4.5, waist: 1.3)
        return p
    }
}
