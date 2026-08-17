import SwiftUI

/// Coaching-insight glyphs skip-ui's Material map has no equivalent for.
///
/// `BehaviorInsight.icon` hands the view layer a raw SF Symbol name; skip-ui
/// maps ~46 symbols and renders a warning triangle for everything else, so
/// `pill.fill`, `waveform.path.ecg` and `lightbulb.fill` all shipped as
/// triangles. Directive 0a says a missing mapping means the closest
/// same-meaning icon — never a different object — and there is no near-enough
/// mapped stand-in for a capsule, a heart trace or a bulb, so they are drawn.
/// Same recipe as `FoodGlyph`/`ChartGlyph`/`ClockGlyph`.
///
/// Geometry: Google Material Symbols (Apache License 2.0, © Google LLC — see
/// Docs/licenses.md), simplified from their 24×24 SVG paths.

/// Medication capsule ("medication" simplified).
///
/// Drawn axis-aligned; call sites tilt it with `.rotationEffect(.degrees(-45))`
/// the way `SupplementsTabView` already does — that diagonal is what separates
/// "a pill" from "a bar" at 13pt. A `CGAffineTransform` inside the Shape would
/// be the tidier expression but Skip's CGAffineTransform bridges only the
/// memberwise init, not the `rotated(by:)` builders.
struct PillShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        var p = Path()
        let body = CGRect(x: ox + 1.5 * s, y: oy + 8 * s, width: 21 * s, height: 8 * s)
        p.addRoundedRect(in: body, cornerSize: CGSize(width: 4 * s, height: 4 * s))
        return p
    }
}

/// Heart-rate trace ("monitor_heart" simplified): a flat baseline broken by one
/// QRS spike. Stroked, not filled — call sites pass a `StrokeStyle`.
struct EcgWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var p = Path()
        p.move(to: pt(1, 12))
        p.addLine(to: pt(6.5, 12))
        p.addLine(to: pt(9, 5))
        p.addLine(to: pt(12, 19))
        p.addLine(to: pt(14.5, 12))
        p.addLine(to: pt(23, 12))
        return p
    }
}

/// Idea bulb ("lightbulb" simplified): a circular glass over a stepped base.
struct LightbulbShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var p = Path()
        // Glass: a disc with a short neck down to the collar.
        p.move(to: pt(8, 14.5))
        p.addArc(center: pt(12, 9), radius: 6.5 * s,
                 startAngle: .degrees(140), endAngle: .degrees(40), clockwise: false)
        p.addLine(to: pt(16, 14.5))
        p.addLine(to: pt(16, 17))
        p.addLine(to: pt(8, 17))
        p.closeSubpath()
        // Screw base: two bars under the collar.
        p.addRect(CGRect(x: ox + 9 * s, y: oy + 18 * s, width: 6 * s, height: 1.6 * s))
        p.addRect(CGRect(x: ox + 10 * s, y: oy + 20.6 * s, width: 4 * s, height: 1.6 * s))
        return p
    }
}
