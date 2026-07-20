import SwiftUI

/// Barbell glyph drawn as a `Path`: skip-ui mapped `dumbbell`/`dumbbell.fill`
/// to `list.bullet`, so every equipment chip, the history card's exercise
/// count, the Browse Exercises row and the Workout TAB ICON ITSELF rendered a
/// bullet-list — a different object entirely, which is exactly the failure the
/// shopping-cart food icon was (operator, 2026-07-19: directive 0a "a missing
/// mapping means find the closest same-meaning icon, not a different object").
///
/// Geometry: Google Material Symbols "fitness_center" (Apache License 2.0, ©
/// Google LLC — see Docs/licenses.md), hand-converted from its 24×24 SVG path
/// to absolute commands. All segments are straight lines, so this renders
/// identically under android.graphics.Path with no winding-rule caveats (the
/// annulus trick ClockFaceShape needs does not apply here).
struct DumbbellShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var p = Path()
        // Bar running lower-left → upper-right, with the two collars/plates at
        // each end (the classic fitness_center barbell silhouette).
        p.move(to: pt(20.57, 14.86))
        p.addLine(to: pt(22, 13.43))
        p.addLine(to: pt(20.57, 12))
        p.addLine(to: pt(17, 15.57))
        p.addLine(to: pt(8.43, 7))
        p.addLine(to: pt(12, 3.43))
        p.addLine(to: pt(10.57, 2))
        p.addLine(to: pt(9.14, 3.43))
        p.addLine(to: pt(7.71, 2))
        p.addLine(to: pt(5.57, 4.14))
        p.addLine(to: pt(4.14, 2.71))
        p.addLine(to: pt(2.71, 4.14))
        p.addLine(to: pt(4.14, 5.57))
        p.addLine(to: pt(2, 7.71))
        p.addLine(to: pt(3.43, 9.14))
        p.addLine(to: pt(2, 10.57))
        p.addLine(to: pt(3.43, 12))
        p.addLine(to: pt(7, 8.43))
        p.addLine(to: pt(15.57, 17))
        p.addLine(to: pt(12, 20.57))
        p.addLine(to: pt(13.43, 22))
        p.addLine(to: pt(14.86, 20.57))
        p.addLine(to: pt(16.29, 22))
        p.addLine(to: pt(18.43, 19.86))
        p.addLine(to: pt(19.86, 21.29))
        p.addLine(to: pt(21.29, 19.86))
        p.addLine(to: pt(19.86, 18.43))
        p.addLine(to: pt(22, 16.29))
        p.closeSubpath()
        return p
    }
}
