import SwiftUI

/// Five-pointed star drawn as a `Path`. skip-ui deliberately disables the
/// outlined Material star (skip-ui #148: `Icons.Outlined.Star` isn't actually
/// outlined), so `sym("star")` falls back to the FILLED star — an un-favorited
/// item then reads as favorited, differing from iOS only by tint. Call sites
/// `.stroke()` this for the outline state and `.fill()` it for the favorited
/// state so the geometry matches across the toggle (directive 0a: the closest
/// same-meaning glyph, never a different object).
struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2 * 0.92
        let inner = outer * 0.40
        var p = Path()
        for i in 0..<10 {
            let angle = -Double.pi / 2 + Double(i) * Double.pi / 5
            let r = i.isMultiple(of: 2) ? outer : inner
            let pt = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}
