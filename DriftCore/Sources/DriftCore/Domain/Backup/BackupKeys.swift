import Foundation

public enum BackupKeys {
    /// UserDefaults keys included in `.driftbackup` archives.
    ///
    /// **Supported shapes** (mirrored in `BackupPackager.jsonSafeValue` /
    /// `BackupRestorer.primitiveValue`): Bool / Int / Double / String /
    /// `[String]` / `Data` (transported as a base64 string with the
    /// `dataB64Prefix` sentinel).
    ///
    /// **Real keys only.** Each entry MUST match a key actually used by
    /// production code (grep `forKey: "..."` to verify). Adding a fictional
    /// dotted-camelCase key here leaks an illusion of breadth without
    /// backing up anything — see the closed root cause for #700.
    public static let userDefaultsAllowlist: [String] = [
        // Units / display
        "weight_unit",                                  // Preferences.weightUnit (String enum raw)
        "drift_weight_chart_calories",                  // Preferences.weightChartCaloriesEnabled (Bool, may be unset)
        "drift_cycle_fertile_window",                   // Preferences.cycleFertileWindow (Bool)

        // AI / chat
        "drift_ai_enabled",                             // Preferences.aiEnabled (Bool)
        "drift_conversation_history_enabled",           // Preferences.conversationHistoryEnabled (Bool)
        "drift_chat_telemetry_enabled",                 // Preferences.chatTelemetryEnabled (Bool)
        "drift_use_remote_model_on_wifi",               // Preferences.useRemoteModelOnWiFi (Bool)
        "drift_preferred_ai_backend",                   // Preferences.preferredAIBackend (String enum raw)

        // Reminders / nudges
        "drift_health_nudges",                          // Preferences.healthNudgesEnabled (Bool)
        "drift_meal_reminders",                         // Preferences.mealRemindersEnabled (Bool)
        "drift_medication_reminders",                   // Preferences.medicationRemindersEnabled (Bool)
        "drift_glp1_reminders",                         // Preferences.glp1RemindersEnabled (Bool)

        // Search / data sources
        "drift_online_food_search",                     // Preferences.onlineFoodSearchEnabled (Bool)
        "drift_usda_api_key",                           // Preferences.usdaApiKey (String)

        // Hydration
        "drift_water_goal_ml",                          // Preferences.waterGoalMl (Double)

        // Goal / planning state — Codable Data blobs (round-trip via dataB64Prefix)
        "drift_weight_goal",                            // WeightGoal Codable Data (Models/WeightGoal.swift)
        "drift_tdee_config",                            // TDEEEstimator.TDEEConfig Codable Data (Domain/Weight/TDEEEstimator.swift)
        "drift_algorithm_config",                       // WeightTrendCalculator.AlgorithmConfig Codable Data (Domain/Weight/WeightTrendCalculator.swift)

        // Workout state
        "drift_custom_exercises",                       // [ExerciseDatabase.ExerciseInfo] Codable Data (Domain/Workout/ExerciseDatabase.swift)
        "drift_exercise_favorites",                     // [String] (Domain/Workout/WorkoutService.swift)
    ]

    /// Sentinel marking a String value in `preferences.json` that decodes back
    /// to `Data`. Chosen to be unambiguous: no production user-facing string
    /// (weight unit, AI backend enum raw, USDA API key) starts with double
    /// underscores. The Restorer treats any String beginning with this prefix
    /// as a base64-encoded payload; on decode failure it drops the entry
    /// silently rather than crashing.
    public static let dataB64Prefix = "__drift_b64__:"

    public static let manifestFileName = "manifest.json"
    public static let databaseFileName = "drift.sqlite"
    public static let preferencesFileName = "preferences.json"
    public static let backupFileExtension = "driftbackup"
}
