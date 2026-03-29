import SwiftUI

/// Shared styling for consistent dark UI.
enum Theme {
    // Colors
    static let background = Color(hex: "1C1C1E")
    static let cardBackground = Color(hex: "2C2C2E")
    static let cardBackgroundElevated = Color(hex: "3A3A3C")
    static let accent = Color(hex: "8B5CF6") // accent purple
    static let deficit = Color(hex: "34D399") // green
    static let surplus = Color(hex: "EF4444") // red
    static let calorieBlue = Color(hex: "3B82F6")
    static let proteinRed = Color(hex: "EF4444")
    static let carbsGreen = Color(hex: "22C55E")
    static let fatYellow = Color(hex: "EAB308")
    static let fiberBrown = Color(hex: "A16207")
    static let sleepIndigo = Color(hex: "818CF8")
    static let stepsOrange = Color(hex: "F97316")
    static let heartRed = Color(hex: "F43F5E")
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

// Card view modifier
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
    }
}

extension View {
    func card() -> some View {
        modifier(CardStyle())
    }
}
