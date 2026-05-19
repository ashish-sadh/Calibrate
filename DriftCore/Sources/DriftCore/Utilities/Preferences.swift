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
                return .lbs
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

    // MARK: - Apple Foundation Models extraction (design-665)

    private static let fmNutritionExtractKey = "drift_fm_nutrition_extract"

    /// When enabled, nutrition label OCR runs through Apple Foundation Models
    /// (`@Generable FMNutritionFacts`) on iOS 26+/macOS 26+ before falling
    /// back to regex. Per design-665 eval: 100% exact-match on US/Indian/
    /// Spanish fixtures, p50 ≈1.9s, fixes non-English regex zero-out bug.
    /// Default: ON. Off-platform / FM-unavailable / flag-off paths all fall
    /// through to the existing regex parser, so this flag is a kill-switch
    /// for users who hit a regression.
    public static var fmNutritionExtractEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: fmNutritionExtractKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: fmNutritionExtractKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: fmNutritionExtractKey) }
    }

    private static let fmWorkoutExtractKey = "drift_fm_workout_extract"

    /// When enabled, free-text workout descriptions route through Apple
    /// Foundation Models (`@Generable FMWorkoutSchema`) on iOS 26+/macOS 26+
    /// before falling back to the regex path. Per design-666 QW3 — unifies
    /// "3x10 bench at 135", "3 sets of 10", "RPE 8", "30 min yoga", "for
    /// half an hour" into one typed call. Kill-switch: flip OFF to revert
    /// to regex everywhere.
    public static var fmWorkoutExtractEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: fmWorkoutExtractKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: fmWorkoutExtractKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: fmWorkoutExtractKey) }
    }

    private static let fmCompositeFoodExtractKey = "drift_fm_composite_food_extract"

    /// When enabled, composite-food queries ("coffee with milk", "biryani
    /// with raita", "idli sambar") route through Apple Foundation Models
    /// (`@Generable FMCompositeFoodSchema`) on iOS 26+/macOS 26+ before
    /// falling back to the hardcoded-connector regex path. Per design-666
    /// QW2 — replaces the static connector list `["served with",
    /// "alongside", "plus", "with"]` with FM understanding of Indian
    /// composites and regional connectors. Kill-switch: flip OFF to revert
    /// to regex everywhere.
    public static var fmCompositeFoodExtractEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: fmCompositeFoodExtractKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: fmCompositeFoodExtractKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: fmCompositeFoodExtractKey) }
    }

    private static let fmFoodIntentExtractKey = "drift_fm_food_intent_extract"

    /// When enabled, free-text food-log messages ("ate 2 eggs", "log 1/3
    /// avocado", "double the rice", "chicken and rice for lunch") route
    /// through Apple Foundation Models (`@Generable FMFoodLogIntentSchema`)
    /// on iOS 26+/macOS 26+ before falling back to the regex chain
    /// (`parseFoodIntent` + `parseMultiFoodIntent` + `extractAmount` +
    /// `matchIngredient` — ~340 LOC). Per design-666 QW1 — collapses the
    /// per-stage regex pipeline into one typed call. Kill-switch: flip OFF
    /// to revert to regex everywhere.
    public static var fmFoodIntentExtractEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: fmFoodIntentExtractKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: fmFoodIntentExtractKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: fmFoodIntentExtractKey) }
    }

    // MARK: - Health Nudges

    private static let healthNudgesKey = "drift_health_nudges"

    public static var healthNudgesEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: healthNudgesKey) }
        set { UserDefaults.standard.set(newValue, forKey: healthNudgesKey) }
    }

    // MARK: - Hydration

    private static let waterGoalMlKey = "drift_water_goal_ml"

    /// Daily water intake goal in millilitres. Default: 2000ml.
    public static var waterGoalMl: Double {
        get {
            let v = UserDefaults.standard.double(forKey: waterGoalMlKey)
            return v > 0 ? v : 2000
        }
        set { UserDefaults.standard.set(newValue, forKey: waterGoalMlKey) }
    }

    // MARK: - Smart Meal Reminders

    private static let mealRemindersKey = "drift_meal_reminders"

    /// Smart meal reminders: contextual "Time to log breakfast" notifications
    /// fired ~30min after the user's typical meal time, only when they
    /// haven't logged that meal yet today. Default OFF — opt-in like
    /// Photo Log Beta. #385 / #690.
    public static var mealRemindersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: mealRemindersKey) }
        set { UserDefaults.standard.set(newValue, forKey: mealRemindersKey) }
    }

    private static let useEatingPatternsForRemindersKey = "drift_meal_reminders_use_patterns"

    /// Sub-toggle for `mealRemindersEnabled`. When ON (default), reminders
    /// fire at the median of the user's recent meal times + 30 min — but
    /// only when 10+ entries exist for that meal in the last 30 days.
    /// When OFF, reminders use fixed defaults (8:30 / 13:00 / 19:30). #690.
    public static var useEatingPatternsForReminders: Bool {
        get {
            // Absent → default to true. New install gets the smart path.
            if UserDefaults.standard.object(forKey: useEatingPatternsForRemindersKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: useEatingPatternsForRemindersKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: useEatingPatternsForRemindersKey) }
    }

    // MARK: - Medication Reminders

    private static let medicationRemindersKey = "drift_medication_reminders"

    /// Smart medication reminders: contextual dose nudge fired ~2h after the
    /// user's typical log time, only when they've logged a medication 3+ times
    /// (consistent pattern) and haven't logged it yet today. Default OFF. #592.
    public static var medicationRemindersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: medicationRemindersKey) }
        set { UserDefaults.standard.set(newValue, forKey: medicationRemindersKey) }
    }

    // MARK: - GLP-1 Reminders

    private static let glp1RemindersKey = "drift_glp1_reminders"

    /// Weekly notification on the user's injection day, only when no dose logged in the last 7 days.
    /// Default OFF. #620.
    public static var glp1RemindersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: glp1RemindersKey) }
        set { UserDefaults.standard.set(newValue, forKey: glp1RemindersKey) }
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

    // MARK: - Remote Model

    private static let useRemoteModelOnWiFiKey = "drift_use_remote_model_on_wifi"

    /// When enabled, AI chat routes through a remote model (Anthropic/OpenAI) on Wi-Fi.
    /// Default: OFF. Not exposed in production UI — architectural prep only.
    public static var useRemoteModelOnWiFi: Bool {
        get { UserDefaults.standard.bool(forKey: useRemoteModelOnWiFiKey) }
        set { UserDefaults.standard.set(newValue, forKey: useRemoteModelOnWiFiKey) }
    }

    // MARK: - Preferred AI Backend (chat routing)

    private static let preferredAIBackendKey = "drift_preferred_ai_backend"

    /// User-selected AI backend for chat. Default: `.foundationModels`
    /// (Apple FM — on-device, system-managed weights, zero per-call cost).
    /// 2026-05-19 migration: was .llamaCpp; now defaults to FoundationModels
    /// on Apple-Intelligence-eligible hardware. Persisted across launches;
    /// flipped by the in-chat cpu/cloud toggle when remote is also available.
    /// Mid-thread changes don't reset history — `LocalAIService` swaps the
    /// underlying backend in place.
    public static var preferredAIBackend: AIBackendType {
        get {
            let raw = UserDefaults.standard.string(forKey: preferredAIBackendKey) ?? ""
            return AIBackendType(rawValue: raw) ?? .foundationModels
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: preferredAIBackendKey) }
    }

    // MARK: - USDA API Key

    private static let usdaApiKeyKey = "drift_usda_api_key"

    /// USDA FoodData Central API key. Register a free key at https://fdc.nal.usda.gov/api-guide.html
    /// to raise the rate limit from 1,000 req/day (DEMO_KEY) to 3,600 req/hour.
    /// When empty, USDAFoodService falls back to DEMO_KEY.
    public static var usdaApiKey: String {
        get { UserDefaults.standard.string(forKey: usdaApiKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: usdaApiKeyKey) }
    }

    // MARK: - Alert dismissed-until timestamps (Unix epoch seconds; 0 = never dismissed)

    public static func alertDismissedUntil(key: String) -> Double {
        UserDefaults.standard.double(forKey: "drift_alert_dismissed_\(key)")
    }

    public static func setAlertDismissedUntil(key: String, until: Double) {
        UserDefaults.standard.set(until, forKey: "drift_alert_dismissed_\(key)")
    }

    // MARK: - Photo Log Beta opt-in

    private static let photoLogEnabledKey = "drift_photo_log_enabled"

    /// Photo Log Beta opt-in. When OFF (default), camera entry points are hidden.
    public static var photoLogEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: photoLogEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: photoLogEnabledKey) }
    }

    // MARK: - Weight Chart calorie overlay

    private static let weightChartCaloriesKey = "drift_weight_chart_calories"

    /// Show daily-calorie bars in the background of the weight chart. When the
    /// user has not explicitly set a value, the default is ON if they've logged
    /// calories on at least 4 of the last 7 days (i.e. they're a regular calorie
    /// tracker, per #669); otherwise OFF.
    public static func weightChartCaloriesEnabled(daysWithCaloriesInLastWeek: Int) -> Bool {
        if let raw = UserDefaults.standard.object(forKey: weightChartCaloriesKey) as? Bool { return raw }
        return daysWithCaloriesInLastWeek >= 4
    }

    public static func setWeightChartCaloriesEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: weightChartCaloriesKey)
    }

    /// True when the user has set the toggle explicitly (used by the UI to
    /// distinguish "auto-on by tracking pattern" from "user opted in").
    public static var weightChartCaloriesUserSet: Bool {
        UserDefaults.standard.object(forKey: weightChartCaloriesKey) != nil
    }

    // MARK: - Install Date + Feedback Prompt (#759)

    private static let installDateKey = "drift_install_date"
    private static let feedbackPromptSeenKey = "drift_feedback_prompt_seen"

    /// Epoch seconds when Drift was first launched on this device. Nil until
    /// `seedInstallDateIfNeeded()` runs (called from app launch). Used to gate
    /// the 7-day Feedback activation banner on the dashboard.
    public static var installDate: Date? {
        get {
            let v = UserDefaults.standard.double(forKey: installDateKey)
            return v > 0 ? Date(timeIntervalSince1970: v) : nil
        }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v.timeIntervalSince1970, forKey: installDateKey)
            } else {
                UserDefaults.standard.removeObject(forKey: installDateKey)
            }
        }
    }

    /// Seed `installDate` to `now` if unset. No-op if a value already exists.
    /// Called once from DriftApp launch so the install timestamp survives
    /// across app updates.
    public static func seedInstallDateIfNeeded(now: Date = Date()) {
        if UserDefaults.standard.double(forKey: installDateKey) <= 0 {
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: installDateKey)
        }
    }

    /// True once the user has tapped (or dismissed) the dashboard Feedback
    /// banner. Banner predicate uses this to suppress redisplay forever.
    public static var hasSeenFeedbackPrompt: Bool {
        get { UserDefaults.standard.bool(forKey: feedbackPromptSeenKey) }
        set { UserDefaults.standard.set(newValue, forKey: feedbackPromptSeenKey) }
    }

    /// Pure predicate: show the dashboard Feedback banner when the user is in
    /// days 7..<14 since install AND hasn't acknowledged it yet. Returns
    /// false when `installDate` is nil, the user has seen it, the window
    /// hasn't opened (< 7 days), or auto-dismiss is past (≥ 14 days). #759.
    public static func shouldShowFeedbackPrompt(now: Date, installDate: Date?, hasSeen: Bool) -> Bool {
        guard let installDate, !hasSeen else { return false }
        let days = now.timeIntervalSince(installDate) / 86400
        return days >= 7 && days < 14
    }
}
