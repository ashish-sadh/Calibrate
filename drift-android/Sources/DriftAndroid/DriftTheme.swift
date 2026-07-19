import SwiftUI

/// Mirror of the iOS Drift/Utilities/Theme.swift palette so the Android app
/// reads as the same product. Keep hex values in sync with iOS Theme until
/// the theme moves into a shared package.
enum DriftTheme {
    static let background = Color(hex: "EFEFF1")
    static let cardBackground = Color.white
    static let accent = Color(hex: "FF375F")
    static let accentSoft = Color(hex: "FFE0E6")
    static let deficit = Color(hex: "30C760")   // aligned with goal = green
    static let textSecondary = Color(hex: "5C5D69")
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}
