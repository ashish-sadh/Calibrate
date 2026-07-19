import SwiftUI

/// Fork-and-knife glyph drawn as a `Path`: skip-ui's Material map has no food
/// icon, and Skip Fuse builds drop `.xcassets` symbolsets from the APK, so the
/// food surfaces draw their own glyph instead of shipping a semantically wrong
/// stand-in (the cart read as SHOPPING — operator, 2026-07-19).
///
/// Geometry: Google Material Symbols "restaurant" (Apache License 2.0, ©
/// Google LLC — see Docs/licenses.md), hand-converted from its 24×24 SVG path
/// to absolute commands.
struct ForkKnifeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var p = Path()
        // Fork: three tines joined at the collar, then the handle.
        p.move(to: pt(11, 9))
        p.addLine(to: pt(9, 9))
        p.addLine(to: pt(9, 2))
        p.addLine(to: pt(7, 2))
        p.addLine(to: pt(7, 9))
        p.addLine(to: pt(5, 9))
        p.addLine(to: pt(5, 2))
        p.addLine(to: pt(3, 2))
        p.addLine(to: pt(3, 9))
        p.addCurve(to: pt(6.75, 12.97), control1: pt(3, 11.12), control2: pt(4.66, 12.84))
        p.addLine(to: pt(6.75, 22))
        p.addLine(to: pt(9.25, 22))
        p.addLine(to: pt(9.25, 12.97))
        p.addCurve(to: pt(13, 9), control1: pt(11.34, 12.84), control2: pt(13, 11.12))
        p.addLine(to: pt(13, 2))
        p.addLine(to: pt(11, 2))
        p.closeSubpath()
        // Knife: blade curve into the handle.
        p.move(to: pt(16, 13))
        p.addLine(to: pt(16, 22))
        p.addLine(to: pt(18.5, 22))
        p.addLine(to: pt(18.5, 2))
        p.addCurve(to: pt(13.5, 7), control1: pt(15.74, 2), control2: pt(13.5, 4.24))
        p.addLine(to: pt(13.5, 13))
        p.closeSubpath()
        return p
    }
}
