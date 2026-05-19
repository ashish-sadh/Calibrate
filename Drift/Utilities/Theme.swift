import SwiftUI

/// Shared styling — V6 light mode (Apple Fitness DNA).
///
/// Migrated from dark on 2026-05-19. Source: Docs/design-references/v6-2026-05-14/v6/v6-theme.jsx
/// V6 spec: "Light-only, Apple Fitness DNA. Soft white surfaces, glassy depth,
/// vivid ring palette. One display family, one body family, mono only for
/// tabular numerics."
///
/// Per Docs/personas/product-designer.md: "Theme is open — not tied to dark-only.
/// Bold redesigns welcome as long as app-wide."
enum Theme {

    // MARK: - Surface Colors (paper white, layered)

    /// Page / scroll bg — soft gray. White cards float on this layer (v7 spec).
    /// Was #FAFAFB (paper white) initially; v7 uses oklch(0.94 0.003 250) so
    /// that #ffffff cards have visual lift via simple contrast rather than
    /// relying on shadows alone.
    static let background = Color(hex: "EFEFF1")
    /// Grouped scroll bg / inset region — slightly lighter than page bg
    /// so nested sections still differentiate.
    static let backgroundGrouped = Color(hex: "F5F5F7")
    /// Card surface — pure white for the most-elevated content.
    static let cardBackground = Color.white
    /// Sub-card surface — inset within a card.
    static let cardBackgroundElevated = Color(hex: "F5F5F7")
    /// Pill / chip background.
    static let pillBackground = Color(hex: "EFEFF1")
    /// Hairline / divider color.
    static let separator = Color(hex: "E5E5E8")
    /// Faint hairline for sub-dividers.
    static let separatorFaint = Color(hex: "EFEFF1")

    // MARK: - Brand & Accent (Apple Fitness red is the V6 accent)

    /// Primary accent — V6 chose Fitness red (the move ring color).
    static let accent = Color(hex: "FF375F")
    /// Soft accent tint background.
    static let accentSoft = Color(hex: "FFE0E6")
    /// Secondary accent — orange (the fat ring color), used sparingly.
    static let accentSecondary = Color(hex: "FF8F2C")

    // MARK: - Ink (V7 black primary CTA / FAB / active-tab)
    //
    // The V7 design moves the primary action color from coral-on-white to
    // black-on-white. Coral still owns "move ring + brand moments" (weight
    // chart line, kcal ring, log-on-empty links), but the FAB, active tab
    // pill, primary buttons ("Suggest a snack", "Open camera", filter
    // pills selected state) all use ink. Net effect: only color in the app
    // chrome maps to either brand (coral) or goal direction (green/red).
    static let ink = Color(hex: "0A0A0A")
    static let inkSoft = Color(hex: "1F1F23")

    // MARK: - Semantic Colors (goal-aware)

    /// Aligned with goal direction (weight loss → green, gain → green if goal=gain).
    static let deficit = Color(hex: "30C760")
    static let deficitSoft = Color(hex: "DFF5E4")
    /// Against goal direction.
    static let surplus = Color(hex: "FF3B30")
    static let surplusSoft = Color(hex: "FFE0DE")
    /// Cautionary (e.g., approaching limits).
    static let warn = Color(hex: "FF9500")
    static let warnSoft = Color(hex: "FFEFD9")

    // MARK: - Macro Colors
    //
    // V7 (May 2026) introduced semantic names — `macroKcal/Protein/Fiber/
    // Carbs/Fat`. The legacy tokens below it (`calorieBlue`, `proteinRed`,
    // `carbsGreen`, `fatYellow`, `fiberBrown`) are misnamed leftovers from
    // an earlier palette. New code should use the `macro*` names; the
    // legacy names are kept as aliases so existing callsites still resolve
    // without a sweeping rename.

    /// Kcal / energy ring → coral.
    static let macroKcal = Color(hex: "FF375F")
    /// Protein ring → green (matches V7 ring palette).
    static let macroProtein = Color(hex: "30C760")
    /// Fiber ring → sky blue. The legacy `fiberBrown` was a muted brown
    /// that didn't match the V7 design's bright-blue fiber dot.
    static let macroFiber = Color(hex: "5BAEEC")
    /// Carbs → amber.
    static let macroCarbs = Color(hex: "F0AD2F")
    /// Fat → orange.
    static let macroFat = Color(hex: "FF8F2C")

    // Legacy aliases — kept to avoid a sweeping callsite rename. Prefer
    // `macroKcal`, `macroProtein`, etc. in new code.
    /// Calorie / energy → red (the "move" ring).
    static let calorieBlue = macroKcal
    /// Protein.
    static let proteinRed = Color(hex: "30A845")
    /// Carbs → amber.
    static let carbsGreen = macroCarbs
    /// Fat → orange.
    static let fatYellow = macroFat
    /// Fiber → muted brown (kept from prior palette).
    static let fiberBrown = Color(hex: "A16207")

    // MARK: - Domain Colors

    static let sleepIndigo = Color(hex: "5856D6")
    static let stepsOrange = Color(hex: "FF9500")
    static let heartRed = Color(hex: "FF375F")
    static let rhythmTeal = Color(hex: "34C7C7")
    static let plantGreen = Color(hex: "30C760")
    static let cyclePink = Color(hex: "FF2D55")
    static let supplementMint = Color(hex: "30C760")

    // MARK: - Text Colors (cool near-black on white)

    /// Primary text — cool near-black. sRGB approx of oklch(0.18 0.012 260).
    static let textPrimary = Color(hex: "1A1B22")
    /// Secondary text — for captions, metadata.
    static let textSecondary = Color(hex: "5C5D69")
    /// Tertiary text — placeholders, disabled, axis labels.
    /// Bumped 2026-05-19 in two passes:
    ///   1) #B6B7BC → #6F7079 (TestFlight 255 visibility pass).
    ///   2) #6F7079 → #595A63 (user feedback: weight-chart x-axis labels
    ///      "Apr May May May" and body-comp stat blocks "-- kg/wk", "Log
    ///      a few more days", "3d 7d 14d 30d 90d" still read as washed-out
    ///      placeholders rather than legible secondary info).
    /// Cool near-black target: oklch(0.36) approx — still differentiates
    /// from textSecondary but no longer falls below the AA contrast floor
    /// for small text on the paper-white background.
    static let textTertiary = Color(hex: "595A63")
    /// Quaternary — for truly disabled / placeholder states only.
    static let textQuaternary = Color(hex: "A6A7AD")

    // MARK: - Typography

    static let fontLargeTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    static let fontTitle = Font.system(size: 20, weight: .bold, design: .rounded)
    static let fontHeadline = Font.system(size: 16, weight: .semibold, design: .rounded)
    static let fontBody = Font.system(size: 15, weight: .regular, design: .default)
    static let fontCaption = Font.system(size: 13, weight: .medium, design: .default)
    static let fontStat = Font.system(size: 22, weight: .bold, design: .rounded).monospacedDigit()
    /// Large numeric display — V6 spec uses tabular for stat numbers.
    static let fontDisplay = Font.system(size: 48, weight: .bold, design: .rounded).monospacedDigit()

    // MARK: - Spacing

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 14
    static let spacingLG: CGFloat = 20
    static let spacingXL: CGFloat = 28

    // MARK: - Card

    static let cardCornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16

    // MARK: - Shadows (V6 glass depth)
    //
    // Apply via View modifiers below: `.shadowSoft()` / `.shadowPop()` /
    // `.shadowRaise()`. The constants live in the modifier definitions so
    // there's a single source of truth (no static factory + duplicate
    // modifier values).

    // MARK: - Score Helpers

    /// Continuous color for a 0-100 score (red -> amber -> green).
    static func scoreColor(_ score: Int) -> Color {
        if score >= 67 { return deficit }
        if score >= 34 { return carbsGreen }
        return surplus
    }

    /// Gradient for score progress bars.
    static let scoreGradient = LinearGradient(
        colors: [surplus, carbsGreen, deficit],
        startPoint: .leading, endPoint: .trailing
    )

    /// Accent gradient for hero elements.
    static let accentGradient = LinearGradient(
        colors: [accent, accentSecondary],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: - V6 Palette (retained for explicit Apple-Fitness ring lookups)

    /// Vivid Apple-Fitness ring palette + soft tint backgrounds. Kept under
    /// Theme.V6 for views that want to address rings by their canonical V6
    /// name (e.g. `Theme.V6.ringMove` reads better than `Theme.calorieBlue`
    /// in dashboard ring code).
    enum V6 {
        static let ringMove = Color(hex: "FF375F")
        static let ringMoveBg = Color(hex: "FFE0E6")
        static let ringEx = Color(hex: "7BE619")
        static let ringExBg = Color(hex: "E2F6CC")
        static let ringStand = Color(hex: "35C4E5")
        static let ringStandBg = Color(hex: "D6EEF7")
        static let ringCarbs = Color(hex: "F0AD2F")
        static let ringCarbsBg = Color(hex: "FAEBC8")
        static let ringFat = Color(hex: "FF8F2C")
        static let ringFatBg = Color(hex: "FCE3CB")
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - V6 shadows (glass depth)

extension View {
    /// V6 soft shadow + hairline. Default for cards.
    func shadowSoft() -> some View {
        self.shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
    /// V6 pop shadow. Sheets / popovers.
    func shadowPop() -> some View {
        self.shadow(color: Color.black.opacity(0.10), radius: 30, x: 0, y: 10)
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
    /// V6 raise shadow. Elevated / hero cards.
    func shadowRaise() -> some View {
        self.shadow(color: Color.black.opacity(0.07), radius: 14, x: 0, y: 4)
    }
}

// MARK: - Card View Modifier

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.cardPadding)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .strokeBorder(Theme.separator, lineWidth: 0.5)
            )
            .shadowSoft()
    }
}

extension View {
    func card() -> some View {
        modifier(CardStyle())
    }
}
