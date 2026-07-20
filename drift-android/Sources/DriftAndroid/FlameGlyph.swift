import SwiftUI

/// Flame glyph drawn as a `Path`: skip-ui's Material map has NO fire icon of
/// any kind (grepped — no flame/fire/whatshot entry), so `sym("flame.fill")`
/// fell back to `star.fill`. A STAR next to "0 active cal" and "1 week streak"
/// reads as a rating or a favourite, not as burn — directive 0a's "different
/// object" failure. The two workout-tab call sites draw this instead.
///
/// Geometry is hand-authored rather than converted from Material's
/// `local_fire_department` (its path is curve-heavy and reproducing it by hand
/// risks a mangled silhouette). The shape is deliberately ASYMMETRIC — leaning
/// tip, notched left shoulder, wide round base — because a symmetric teardrop
/// reads as a water droplet, which would just trade one wrong object for
/// another.
struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var p = Path()
        p.move(to: pt(13, 2))
        // Left shoulder: S-curve down from the leaning tip into the notch.
        p.addCurve(to: pt(8.5, 9.5), control1: pt(12.5, 5), control2: pt(10, 7))
        // Out to the left belly.
        p.addCurve(to: pt(5, 15.5), control1: pt(7, 12), control2: pt(5, 13))
        // Round base, left to bottom.
        p.addCurve(to: pt(12, 22), control1: pt(5, 19.5), control2: pt(8, 22))
        // Base, bottom to right belly.
        p.addCurve(to: pt(19, 15), control1: pt(16.5, 22), control2: pt(19, 19))
        // Right side sweeping up.
        p.addCurve(to: pt(14.8, 7.5), control1: pt(19, 11.5), control2: pt(16.5, 9.5))
        // Back into the tip.
        p.addCurve(to: pt(13, 2), control1: pt(14, 5.5), control2: pt(13.8, 4))
        p.closeSubpath()
        return p
    }
}
