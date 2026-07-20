import Foundation

public enum WeightUnit: String, CaseIterable, Codable, Sendable {
    case kg
    case lbs

    public var displayName: String {
        switch self {
        case .kg: "kg"
        case .lbs: "lbs"
        }
    }

    public func convert(fromKg kg: Double) -> Double {
        switch self {
        case .kg: kg
        case .lbs: kg * 2.20462
        }
    }

    public func convertToKg(_ value: Double) -> Double {
        switch self {
        case .kg: value
        case .lbs: value / 2.20462
        }
    }

    /// Convert exercise weight from storage (lbs) to display unit
    public func convertFromLbs(_ lbs: Double) -> Double {
        switch self {
        case .lbs: lbs
        case .kg: lbs / 2.20462
        }
    }

    /// Convert exercise weight from user input to storage (lbs)
    public func convertToLbs(_ value: Double) -> Double {
        switch self {
        case .lbs: value
        case .kg: value * 2.20462
        }
    }

    // MARK: - Set-weight field round-trip

    /// The two halves of a typed set-weight field. Storage is always lbs
    /// (`WorkoutSet.weightLbs`); the field carries the user's unit.
    ///
    /// They are inverses and MUST be used as a pair. The prefill once wrote
    /// the raw *stored lbs* number into a kg-labelled field while the reader
    /// converted that text as kg — so every kg user's log grew 2.20462x per
    /// save, silently, with no user input (#1084). Keeping both directions
    /// here means a later caller cannot convert one way and forget the other.

    /// Field text in this unit → stored lbs. Accepts comma decimals (#1022).
    /// nil for blank, non-numeric, or non-positive input.
    public func entryTextToLbs(_ text: String) -> Double? {
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
        return convertToLbs(v)
    }

    /// Stored lbs → field text in this unit. Inverse of `entryTextToLbs`.
    public func entryText(fromLbs lbs: Double) -> String {
        WeightFormatter.plain(convertFromLbs(lbs))
    }
}
