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

    /// Convert exercise weight from storage (lbs) to display unit
    func convertFromLbs(_ lbs: Double) -> Double {
        switch self {
        case .lbs: lbs
        case .kg: lbs / 2.20462
        }
    }

    /// Convert exercise weight from user input to storage (lbs)
    func convertToLbs(_ value: Double) -> Double {
        switch self {
        case .lbs: value
        case .kg: value * 2.20462
        }
    }
}

enum Preferences {
    private static let weightUnitKey = "weight_unit"
    private static let cycleFertileWindowKey = "drift_cycle_fertile_window"

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

    static var cycleFertileWindow: Bool {
        get { UserDefaults.standard.bool(forKey: cycleFertileWindowKey) }
        set { UserDefaults.standard.set(newValue, forKey: cycleFertileWindowKey) }
    }

    private static let aiEnabledKey = "drift_ai_enabled"

    static var aiEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: aiEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: aiEnabledKey) }
    }

    private static let onlineFoodSearchKey = "drift_online_food_search"

    /// When enabled, food search queries are sent to USDA and Open Food Facts APIs
    /// when local results are insufficient. Default: ON.
    static var onlineFoodSearchEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: onlineFoodSearchKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: onlineFoodSearchKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: onlineFoodSearchKey) }
    }

    private static let healthNudgesKey = "drift_health_nudges"

    /// When enabled, local push notifications remind users about protein streaks,
    /// supplement gaps, and workout gaps. Default: OFF.
    static var healthNudgesEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: healthNudgesKey) }
        set { UserDefaults.standard.set(newValue, forKey: healthNudgesKey) }
    }

    private static let conversationHistoryEnabledKey = "drift_conversation_history_enabled"

    /// When enabled, the last few chat turns are threaded into LLM prompts so
    /// follow-ups like "what about protein?" resolve in context. Default: ON.
    static var conversationHistoryEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: conversationHistoryEnabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: conversationHistoryEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: conversationHistoryEnabledKey) }
    }
}
