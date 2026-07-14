import Foundation

/// Forgiving unit parsing for user-typed values — "take whatever" (operator
/// 2026-07-14). A bare number keeps the surface's default unit; an explicit
/// suffix always wins, so someone who knows their waist in cm can type
/// "86cm" on an inches form and someone lifting metric plates can type
/// "60kg" in a lbs workout. Comma decimals accepted (#1022).
public enum FlexibleUnitInput {

    /// Split "34.5 in" → (34.5, "in"). nil when no leading number.
    static func split(_ text: String) -> (value: Double, suffix: String)? {
        let t = text.lowercased()
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = t.range(of: #"^\d*\.?\d+"#, options: .regularExpression),
              let value = Double(String(t[match])) else { return nil }
        let suffix = String(t[match.upperBound...])
            .trimmingCharacters(in: CharacterSet(charactersIn: " .·"))
        return (value, suffix)
    }

    // MARK: - Body-length input (tape measurements)

    /// Parse a measurement as centimetres. Bare numbers use `assumeInches`;
    /// explicit cm/in/mm suffixes override it. Unknown suffixes return nil
    /// (never guess a unit for junk like "34 asdf").
    public static func lengthCm(from text: String, assumeInches: Bool) -> Double? {
        guard let (value, suffix) = split(text), value > 0 else { return nil }
        switch suffix {
        case "": return assumeInches ? value * 2.54 : value
        case "cm", "cms", "centimeter", "centimeters", "centimetre", "centimetres":
            return value
        case "in", "ins", "inch", "inches", "\"", "\u{201D}", "\u{2033}":
            return value * 2.54
        case "mm":
            return value / 10
        default:
            return nil
        }
    }

    // MARK: - Workout weight input

    /// Parse a lifted weight as pounds (the unit `WorkoutSet.weightLbs`
    /// stores and the workout UI displays). Bare numbers stay lbs — that's
    /// the long-standing meaning of the field; an explicit kg suffix
    /// converts.
    public static func weightLbs(from text: String) -> Double? {
        guard let (value, suffix) = split(text) else { return nil }
        switch suffix {
        case "", "lb", "lbs", "#", "pound", "pounds":
            return value
        case "kg", "kgs", "kilo", "kilos", "kilogram", "kilograms":
            return value * 2.20462
        default:
            return nil
        }
    }
}
