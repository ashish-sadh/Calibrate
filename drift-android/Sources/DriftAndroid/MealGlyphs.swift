import SwiftUI
import DriftCore

/// Meal-type + plant glyphs drawn as `Path`s: skip-ui's Material map (73
/// symbols) has no sun, moon, cup, or leaf icon, so the ported Food surfaces'
/// meal icons (`MealType.icon` — sunrise / sun.max / moon.stars /
/// cup.and.saucer) and the plant-points leaf would all render as warning
/// triangles. Same convention as ForkKnifeShape/ClockFaceShape: simplified
/// Google Material Symbols geometry (Apache License 2.0, © Google LLC — see
/// Docs/licenses.md), 24×24 grid, fill paths. Rings/crescents use
/// opposite-wound arc pairs because skip-ui has no even-odd fill and a single
/// 360° sweep collapses to 0° mod 360 in android.graphics.Path.arcTo.

/// Half-sun over a horizon line ("wb_twilight" simplified).
struct SunriseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var p = Path()
        // Half-disc sun sitting on the horizon.
        p.move(to: pt(7, 16))
        p.addArc(center: pt(12, 16), radius: 5 * s,
                 startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        p.closeSubpath()
        // Horizon bar.
        p.addRect(CGRect(x: ox + 3 * s, y: oy + 18 * s, width: 18 * s, height: 1.8 * s))
        // Rays: vertical + two diagonals above the disc.
        p.addRect(CGRect(x: ox + 11.2 * s, y: oy + 4 * s, width: 1.6 * s, height: 4 * s))
        p.move(to: pt(4.6, 8.4)); p.addLine(to: pt(5.8, 7.2))
        p.addLine(to: pt(8.4, 9.8)); p.addLine(to: pt(7.2, 11)); p.closeSubpath()
        p.move(to: pt(19.4, 8.4)); p.addLine(to: pt(18.2, 7.2))
        p.addLine(to: pt(15.6, 9.8)); p.addLine(to: pt(16.8, 11)); p.closeSubpath()
        return p
    }
}

/// Full sun with eight rays ("light_mode" simplified).
struct SunMaxShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        let center = CGPoint(x: ox + 12 * s, y: oy + 12 * s)
        var p = Path()
        // Disc — two opposite-wound half arcs (see file header).
        p.move(to: CGPoint(x: ox + 17 * s, y: oy + 12 * s))
        p.addArc(center: center, radius: 5 * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addArc(center: center, radius: 5 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        p.closeSubpath()
        // Four cardinal rays.
        p.addRect(CGRect(x: ox + 11.2 * s, y: oy + 2 * s, width: 1.6 * s, height: 4 * s))
        p.addRect(CGRect(x: ox + 11.2 * s, y: oy + 18 * s, width: 1.6 * s, height: 4 * s))
        p.addRect(CGRect(x: ox + 2 * s, y: oy + 11.2 * s, width: 4 * s, height: 1.6 * s))
        p.addRect(CGRect(x: ox + 18 * s, y: oy + 11.2 * s, width: 4 * s, height: 1.6 * s))
        // Four diagonal rays.
        func ray(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            let dx = (y2 - y1) * 0.4, dy = (x2 - x1) * 0.4
            p.move(to: CGPoint(x: ox + (x1 - dx) * s, y: oy + (y1 + dy) * s))
            p.addLine(to: CGPoint(x: ox + (x1 + dx) * s, y: oy + (y1 - dy) * s))
            p.addLine(to: CGPoint(x: ox + (x2 + dx) * s, y: oy + (y2 - dy) * s))
            p.addLine(to: CGPoint(x: ox + (x2 - dx) * s, y: oy + (y2 + dy) * s))
            p.closeSubpath()
        }
        ray(4.5, 4.5, 6.6, 6.6)
        ray(17.4, 17.4, 19.5, 19.5)
        ray(19.5, 4.5, 17.4, 6.6)
        ray(6.6, 17.4, 4.5, 19.5)
        return p
    }
}

/// Crescent moon ("dark_mode" simplified): full disc minus an offset disc,
/// via non-zero winding (outer counter-clockwise, cutter clockwise).
struct MoonStarsShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        let center = CGPoint(x: ox + 11 * s, y: oy + 12 * s)
        let cutter = CGPoint(x: ox + 16 * s, y: oy + 9 * s)
        var p = Path()
        p.move(to: CGPoint(x: ox + 20 * s, y: oy + 12 * s))
        p.addArc(center: center, radius: 9 * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addArc(center: center, radius: 9 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        p.closeSubpath()
        p.move(to: CGPoint(x: cutter.x + 7.5 * s, y: cutter.y))
        p.addArc(center: cutter, radius: 7.5 * s, startAngle: .degrees(360), endAngle: .degrees(180), clockwise: true)
        p.addArc(center: cutter, radius: 7.5 * s, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// Mug on a saucer ("local_cafe" simplified): filled body, handle stub,
/// saucer bar.
struct CupSaucerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var p = Path()
        // Body: straight sides, gently rounded bottom.
        p.move(to: pt(4, 5))
        p.addLine(to: pt(16, 5))
        p.addLine(to: pt(16, 13))
        p.addCurve(to: pt(13, 16), control1: pt(16, 14.66), control2: pt(14.66, 16))
        p.addLine(to: pt(7, 16))
        p.addCurve(to: pt(4, 13), control1: pt(5.34, 16), control2: pt(4, 14.66))
        p.closeSubpath()
        // Handle: outer ring segment minus inner (opposite winding).
        p.move(to: pt(16, 6.5))
        p.addArc(center: pt(16, 9.25), radius: 2.75 * s,
                 startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: pt(16, 10.5))
        p.addArc(center: pt(16, 9.25), radius: 1.25 * s,
                 startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
        p.closeSubpath()
        // Saucer.
        p.addRect(CGRect(x: ox + 4 * s, y: oy + 18 * s, width: 16 * s, height: 1.8 * s))
        return p
    }
}

/// Leaf with a stem ("eco" simplified): pointed oval with curved veinless
/// body reads as a leaf at chip sizes.
struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var p = Path()
        // Body: tip top-right, belly bottom-left.
        p.move(to: pt(20, 4))
        p.addCurve(to: pt(7, 17), control1: pt(20, 12), control2: pt(15, 17))
        p.addCurve(to: pt(20, 4), control1: pt(5, 10), control2: pt(11, 4))
        p.closeSubpath()
        // Stem.
        p.move(to: pt(7.6, 15.4))
        p.addCurve(to: pt(4.6, 20.4), control1: pt(6, 17), control2: pt(5, 18.6))
        p.addLine(to: pt(6.2, 21.2))
        p.addCurve(to: pt(9, 16.6), control1: pt(6.8, 19.4), control2: pt(7.6, 18))
        p.closeSubpath()
        return p
    }
}

/// The shared Food surfaces' meal icon: one view per `MealType`, colored and
/// sized by the caller the way `Image(systemName: meal.icon)` would be.
struct MealGlyph: View {
    let meal: MealType
    var color: Color = Theme.textSecondary
    var size: CGFloat = 12

    var body: some View {
        Group {
            switch meal {
            case .breakfast: SunriseShape().fill(color)
            case .lunch: SunMaxShape().fill(color)
            case .dinner: MoonStarsShape().fill(color)
            case .snack: CupSaucerShape().fill(color)
            }
        }
        .frame(width: size, height: size)
    }
}
