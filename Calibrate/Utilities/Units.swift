import Foundation

enum WeightUnit: String, CaseIterable, Codable, Sendable {
    case kg
    case lbs

    var displayName: String {
        switch self {
        case .kg: "kg"
        case .lbs: "lbs"
        }
    }

    func convert(fromKg kg: Double) -> Double {
        switch self {
        case .kg: kg
        case .lbs: kg * 2.20462
        }
    }

    func convertToKg(_ value: Double) -> Double {
        switch self {
        case .kg: value
        case .lbs: value / 2.20462
        }
    }
}

enum Preferences {
    private static let weightUnitKey = "weight_unit"

    static var weightUnit: WeightUnit {
        get {
            guard let raw = UserDefaults.standard.string(forKey: weightUnitKey),
                  let unit = WeightUnit(rawValue: raw) else {
                return .kg
            }
            return unit
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: weightUnitKey)
        }
    }
}
