import Foundation

/// User preferences persisted in `UserDefaults`. Cross-platform — UserDefaults
/// works on macOS too. Photo Log preferences (which depend on the iOS-only
/// `CloudVisionProvider` enum) live in a Drift-side extension.
public enum Preferences {

    // MARK: - Weight Unit

    private static let weightUnitKey = "weight_unit"

    public static var weightUnit: WeightUnit {
        get {
            guard let raw = UserDefaults.standard.string(forKey: weightUnitKey),
                  let unit = WeightUnit(rawValue: raw) else {
                return .kg
            }
            return unit
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: weightUnitKey) }
    }

    // MARK: - Cycle

    private static let cycleFertileWindowKey = "drift_cycle_fertile_window"

    public static var cycleFertileWindow: Bool {
        get { UserDefaults.standard.bool(forKey: cycleFertileWindowKey) }
        set { UserDefaults.standard.set(newValue, forKey: cycleFertileWindowKey) }
    }

    // MARK: - AI

    private static let aiEnabledKey = "drift_ai_enabled"

    public static var aiEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: aiEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: aiEnabledKey) }
    }

    // MARK: - Online Food Search

    private static let onlineFoodSearchKey = "drift_online_food_search"

    /// When enabled, food search queries are sent to USDA and Open Food Facts APIs
    /// when local results are insufficient. Default: ON.
    public static var onlineFoodSearchEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: onlineFoodSearchKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: onlineFoodSearchKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: onlineFoodSearchKey) }
    }

    // MARK: - Health Nudges

    private static let healthNudgesKey = "drift_health_nudges"

    public static var healthNudgesEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: healthNudgesKey) }
        set { UserDefaults.standard.set(newValue, forKey: healthNudgesKey) }
    }

    // MARK: - Conversation History

    private static let conversationHistoryEnabledKey = "drift_conversation_history_enabled"

    public static var conversationHistoryEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: conversationHistoryEnabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: conversationHistoryEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: conversationHistoryEnabledKey) }
    }

    // MARK: - Chat Telemetry

    private static let chatTelemetryEnabledKey = "drift_chat_telemetry_enabled"

    public static var chatTelemetryEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: chatTelemetryEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: chatTelemetryEnabledKey) }
    }

    // MARK: - Photo Log Beta opt-in

    private static let photoLogEnabledKey = "drift_photo_log_enabled"

    /// Photo Log Beta opt-in. When OFF (default), camera entry points are hidden.
    public static var photoLogEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: photoLogEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: photoLogEnabledKey) }
    }
}
