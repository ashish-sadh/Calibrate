import Foundation

/// User preferences persisted in `UserDefaults`. Cross-platform — UserDefaults
/// works on macOS too. Photo Log preferences (which depend on the iOS-only
/// `CloudVisionProvider` enum) live in a Drift-side extension.
public enum Preferences {

    /// All reads/writes route through the platform key–value seam: on iOS/macOS
    /// the default store forwards to `UserDefaults.standard` (behaviour
    /// unchanged), on Android a SQLite-backed store, because Skip Fuse's
    /// SharedPreferences never durably persists (#1108).
    private static var kv: KeyValueStore { DriftPlatform.keyValueStore }

    // MARK: - Weight Unit

    private static let weightUnitKey = "weight_unit"

    public static var weightUnit: WeightUnit {
        get {
            guard let raw = kv.string(forKey: weightUnitKey),
                  let unit = WeightUnit(rawValue: raw) else {
                return .lbs
            }
            return unit
        }
        set { kv.set(newValue.rawValue, forKey: weightUnitKey) }
    }

    // MARK: - Cycle

    private static let cycleFertileWindowKey = "drift_cycle_fertile_window"

    public static var cycleFertileWindow: Bool {
        get { kv.bool(forKey: cycleFertileWindowKey) }
        set { kv.set(newValue, forKey: cycleFertileWindowKey) }
    }

    // MARK: - AI

    private static let aiEnabledKey = "drift_ai_enabled"

    // 2026-05-19: default flipped false → true (Apple FoundationModels
    // migration). When AI lived behind a local-model download flow, opt-in
    // made sense — it was the user agreeing to download ~1GB of weights.
    // With Apple FM the model is system-managed, on-device, and always
    // available; there is nothing to opt into. Mirrors the @AppStorage
    // flip in ContentView.swift + DashboardView.swift.
    public static var aiEnabled: Bool {
        get { kv.boolOrNil(forKey: aiEnabledKey) ?? true }
        set { kv.set(newValue, forKey: aiEnabledKey) }
    }

    // MARK: - Online Food Search

    private static let onlineFoodSearchKey = "drift_online_food_search"

    /// When enabled, food search queries are sent to USDA and Open Food Facts APIs
    /// when local results are insufficient. Default: ON.
    public static var onlineFoodSearchEnabled: Bool {
        get {
            if !kv.hasValue(forKey: onlineFoodSearchKey) { return true }
            return kv.bool(forKey: onlineFoodSearchKey)
        }
        set { kv.set(newValue, forKey: onlineFoodSearchKey) }
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
            if !kv.hasValue(forKey: fmNutritionExtractKey) { return true }
            return kv.bool(forKey: fmNutritionExtractKey)
        }
        set { kv.set(newValue, forKey: fmNutritionExtractKey) }
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
            if !kv.hasValue(forKey: fmWorkoutExtractKey) { return true }
            return kv.bool(forKey: fmWorkoutExtractKey)
        }
        set { kv.set(newValue, forKey: fmWorkoutExtractKey) }
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
            if !kv.hasValue(forKey: fmCompositeFoodExtractKey) { return true }
            return kv.bool(forKey: fmCompositeFoodExtractKey)
        }
        set { kv.set(newValue, forKey: fmCompositeFoodExtractKey) }
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
            if !kv.hasValue(forKey: fmFoodIntentExtractKey) { return true }
            return kv.bool(forKey: fmFoodIntentExtractKey)
        }
        set { kv.set(newValue, forKey: fmFoodIntentExtractKey) }
    }

    // MARK: - Health Nudges

    private static let healthNudgesKey = "drift_health_nudges"

    public static var healthNudgesEnabled: Bool {
        get { kv.bool(forKey: healthNudgesKey) }
        set { kv.set(newValue, forKey: healthNudgesKey) }
    }

    // MARK: - Hydration

    private static let waterGoalMlKey = "drift_water_goal_ml"

    /// Daily water intake goal in millilitres. Default: 2000ml.
    public static var waterGoalMl: Double {
        get {
            let v = kv.double(forKey: waterGoalMlKey)
            return v > 0 ? v : 2000
        }
        set { kv.set(newValue, forKey: waterGoalMlKey) }
    }

    // MARK: - Coach Voice / Talk Mode

    private static let coachVoiceKey = "drift_coach_voice_enabled"
    private static let coachVoiceV2MigratedKey = "drift_coach_voice_v2_migrated"
    private static let coachVoiceV3MigratedKey = "drift_coach_voice_v3_migrated"

    /// Drift Coach voice: when ON, the coach speaks its replies aloud
    /// (ElevenLabs when provisioned, on-device TTS fallback). The speaker
    /// toggle in the chat input bar is the SINGLE source of truth for spoken
    /// replies — typed turns, mic turns, and talk mode all honor it (operator
    /// call 2026-07-11). Default ON: a voice-first coach that ships mute reads
    /// as broken (field report 2026-07-10).
    public static var coachVoiceEnabled: Bool {
        get {
            guard kv.hasValue(forKey: coachVoiceKey) else { return true }
            return kv.bool(forKey: coachVoiceKey)
        }
        set { kv.set(newValue, forKey: coachVoiceKey) }
    }

    /// One-time migrations for the coach voice flag.
    /// v2 (#968): the pre-#937 bug persistently wrote coachVoiceEnabled=true
    /// even when voice was meant off — reset affected devices.
    /// v3 (2026-07-11): v2 stamped FALSE onto every install, which — combined
    /// with all speak paths gating on this one flag — shipped a mute coach.
    /// Clear the stored value once so everyone picks up the new default-ON;
    /// from here the speaker toggle records real user choice and persists
    /// normally.
    public static func migrateCoachVoiceIfNeeded() {
        if !kv.bool(forKey: coachVoiceV2MigratedKey) {
            kv.set(false, forKey: coachVoiceKey)
            kv.set(true, forKey: coachVoiceV2MigratedKey)
        }
        if !kv.bool(forKey: coachVoiceV3MigratedKey) {
            kv.removeObject(forKey: coachVoiceKey)
            kv.set(true, forKey: coachVoiceV3MigratedKey)
        }
    }

    private static let coachTalkModeKey = "drift_coach_talk_mode_enabled"

    /// Immersive voice talk-mode: when ON, Drift Coach drops the chat log + input
    /// bar for a full-screen "tap to talk" circle and runs a hands-free loop
    /// (listen → answer aloud → keep listening). A superset of `coachVoiceEnabled`
    /// (turning it on implies voice replies). Toggled by the speaker button at the
    /// top of the coach. Default OFF. #coach-talk-mode.
    public static var coachTalkModeEnabled: Bool {
        get { kv.bool(forKey: coachTalkModeKey) }
        set { kv.set(newValue, forKey: coachTalkModeKey) }
    }

    private static let coachCloudFoodParseKey = "drift_coach_cloud_food_parse_enabled"

    /// Whether text/voice food logging parses descriptions with the Drift Coach
    /// cloud model (Nebius). Default ON when a key is provisioned. Off → falls
    /// back to the on-device extractor / ad-hoc entry (also lets unit tests force
    /// the offline path). #food-logging-reuse
    public static var coachCloudFoodParseEnabled: Bool {
        get { kv.boolOrNil(forKey: coachCloudFoodParseKey) ?? true }
        set { kv.set(newValue, forKey: coachCloudFoodParseKey) }
    }

    private static let mealRemindersKey = "drift_meal_reminders"

    /// Smart meal reminders: contextual "Time to log breakfast" notifications
    /// fired ~30min after the user's typical meal time, only when they
    /// haven't logged that meal yet today. Default OFF — opt-in like
    /// Photo Log Beta. #385 / #690.
    public static var mealRemindersEnabled: Bool {
        get { kv.bool(forKey: mealRemindersKey) }
        set { kv.set(newValue, forKey: mealRemindersKey) }
    }

    private static let useEatingPatternsForRemindersKey = "drift_meal_reminders_use_patterns"

    /// Sub-toggle for `mealRemindersEnabled`. When ON (default), reminders
    /// fire at the median of the user's recent meal times + 30 min — but
    /// only when 10+ entries exist for that meal in the last 30 days.
    /// When OFF, reminders use fixed defaults (8:30 / 13:00 / 19:30). #690.
    public static var useEatingPatternsForReminders: Bool {
        get {
            // Absent → default to true. New install gets the smart path.
            if !kv.hasValue(forKey: useEatingPatternsForRemindersKey) { return true }
            return kv.bool(forKey: useEatingPatternsForRemindersKey)
        }
        set { kv.set(newValue, forKey: useEatingPatternsForRemindersKey) }
    }

    // MARK: - Medication Reminders

    private static let medicationRemindersKey = "drift_medication_reminders"

    /// Smart medication reminders: contextual dose nudge fired ~2h after the
    /// user's typical log time, only when they've logged a medication 3+ times
    /// (consistent pattern) and haven't logged it yet today. Default OFF. #592.
    public static var medicationRemindersEnabled: Bool {
        get { kv.bool(forKey: medicationRemindersKey) }
        set { kv.set(newValue, forKey: medicationRemindersKey) }
    }

    // MARK: - GLP-1 Reminders

    private static let glp1RemindersKey = "drift_glp1_reminders"

    /// Weekly notification on the user's injection day, only when no dose logged in the last 7 days.
    /// Default OFF. #620.
    public static var glp1RemindersEnabled: Bool {
        get { kv.bool(forKey: glp1RemindersKey) }
        set { kv.set(newValue, forKey: glp1RemindersKey) }
    }

    // MARK: - Conversation History

    private static let conversationHistoryEnabledKey = "drift_conversation_history_enabled"

    public static var conversationHistoryEnabled: Bool {
        get {
            if !kv.hasValue(forKey: conversationHistoryEnabledKey) { return true }
            return kv.bool(forKey: conversationHistoryEnabledKey)
        }
        set { kv.set(newValue, forKey: conversationHistoryEnabledKey) }
    }

    // MARK: - Chat Telemetry

    private static let chatTelemetryEnabledKey = "drift_chat_telemetry_enabled"

    public static var chatTelemetryEnabled: Bool {
        get { kv.bool(forKey: chatTelemetryEnabledKey) }
        set { kv.set(newValue, forKey: chatTelemetryEnabledKey) }
    }

    // MARK: - Remote Model

    private static let useRemoteModelOnWiFiKey = "drift_use_remote_model_on_wifi"

    /// When enabled, AI chat routes through a remote model (Anthropic/OpenAI) on Wi-Fi.
    /// Default: OFF. Not exposed in production UI — architectural prep only.
    public static var useRemoteModelOnWiFi: Bool {
        get { kv.bool(forKey: useRemoteModelOnWiFiKey) }
        set { kv.set(newValue, forKey: useRemoteModelOnWiFiKey) }
    }

    // MARK: - Preferred AI Backend (chat routing)

    private static let preferredAIBackendKey = "drift_preferred_ai_backend"

    /// User-selected AI backend for chat. Default: `.llamaCpp` (on-device
    /// Gemma 4 / SmolLM2 — the proven baseline). #872 NO-GO reverted the
    /// default off Apple Foundation Models, which measured below the parity
    /// bar; `.foundationModels` stays a selectable backend that must re-earn
    /// the cutover gate before it can become the default again. Persisted
    /// across launches; flipped by the in-chat cpu/cloud toggle when remote
    /// is also available. Mid-thread changes don't reset history —
    /// `LocalAIService` swaps the underlying backend in place.
    public static var preferredAIBackend: AIBackendType {
        get {
            let raw = kv.string(forKey: preferredAIBackendKey) ?? ""
            return AIBackendType(rawValue: raw) ?? .llamaCpp
        }
        set { kv.set(newValue.rawValue, forKey: preferredAIBackendKey) }
    }

    // MARK: - FM NO-GO one-time migration (#872)

    private static let didRunFMNoGoMigrationKey = "drift_did_run_fm_nogo_migration"

    /// One-shot marker for the #872 FM NO-GO migration, run from the DriftApp
    /// launch task. The 2026-05-19 cutover silently force-migrated existing
    /// `.llamaCpp` users onto Apple Foundation Models as the global default;
    /// the NO-GO reverts that default to the on-device Gemma/llama.cpp baseline
    /// (FM measured below the parity bar on the chat surface). On the first
    /// launch carrying the revert we reset any persisted `.foundationModels`
    /// preference so the user lands on the on-device download chooser instead
    /// of a dead / silently sub-bar FM chat. Runs once; default false.
    public static var didRunFMNoGoMigration: Bool {
        get { kv.bool(forKey: didRunFMNoGoMigrationKey) }
        set { kv.set(newValue, forKey: didRunFMNoGoMigrationKey) }
    }

    // MARK: - Coach cloud-first one-time default (#coach-speed)

    private static let didDefaultCoachToCloudKey = "drift_did_default_coach_to_cloud"

    /// One-shot marker: on the first launch carrying a provisioned Nebius team
    /// key, the chat backend default flips from on-device `.llamaCpp` to the
    /// `.remote` cloud brain — even if a local model was previously downloaded.
    /// The on-device path is the *fallback*, not the default (it's slow on A19
    /// Pro where Metal degrades to CPU). One-time so a later explicit on-device
    /// pick is never clobbered. Default false.
    public static var didDefaultCoachToCloud: Bool {
        get { kv.bool(forKey: didDefaultCoachToCloudKey) }
        set { kv.set(newValue, forKey: didDefaultCoachToCloudKey) }
    }

    // MARK: - USDA API Key

    private static let usdaApiKeyKey = "drift_usda_api_key"

    /// USDA FoodData Central API key. Register a free key at https://fdc.nal.usda.gov/api-guide.html
    /// to raise the rate limit from 1,000 req/day (DEMO_KEY) to 3,600 req/hour.
    /// When empty, USDAFoodService falls back to DEMO_KEY.
    public static var usdaApiKey: String {
        get { kv.string(forKey: usdaApiKeyKey) ?? "" }
        set { kv.set(newValue, forKey: usdaApiKeyKey) }
    }

    // MARK: - Web Search API Keys (coach web_search provider ladder)

    private static let braveSearchApiKeyKey = "drift_brave_search_api_key"
    private static let googleSearchApiKeyKey = "drift_google_search_api_key"
    private static let googleSearchEngineIdKey = "drift_google_search_engine_id"

    /// Google Custom Search JSON API key (console.cloud.google.com → enable
    /// "Custom Search API"). Needs `googleSearchEngineId` alongside. Free 100
    /// queries/day. Preferred rung of the web_search ladder when both are set.
    public static var googleSearchApiKey: String {
        get { kv.string(forKey: googleSearchApiKeyKey) ?? "" }
        set { kv.set(newValue, forKey: googleSearchApiKeyKey) }
    }

    /// Programmable Search Engine ID (`cx`) from programmablesearchengine.google.com
    /// — create an engine with "Search the entire web" enabled.
    public static var googleSearchEngineId: String {
        get { kv.string(forKey: googleSearchEngineIdKey) ?? "" }
        set { kv.set(newValue, forKey: googleSearchEngineIdKey) }
    }

    /// Brave Search API key — alternate ladder rung (https://brave.com/search/api/,
    /// free ~2k queries/mo). When no provider is keyed, web_search degrades to
    /// DuckDuckGo Instant Answers (keyless, weak for nutrition). Same
    /// UserDefaults pattern as `usdaApiKey`.
    public static var braveSearchApiKey: String {
        get { kv.string(forKey: braveSearchApiKeyKey) ?? "" }
        set { kv.set(newValue, forKey: braveSearchApiKeyKey) }
    }

    // MARK: - Alert dismissed-until timestamps (Unix epoch seconds; 0 = never dismissed)

    public static func alertDismissedUntil(key: String) -> Double {
        kv.double(forKey: "drift_alert_dismissed_\(key)")
    }

    public static func setAlertDismissedUntil(key: String, until: Double) {
        kv.set(until, forKey: "drift_alert_dismissed_\(key)")
    }

    // MARK: - Apple Health nutrition write-back (#934)

    private static let healthNutritionWriteKey = "drift_health_nutrition_write"
    private static let healthNutritionAutoDisableKey = "drift_health_nutrition_auto_disable_reason"

    /// Write logged nutrition (dietary calories + protein/carbs/fat/fiber) to
    /// Apple Health as entries are saved. OFF by default — the user opts in
    /// from Settings; the writer also auto-disables this (recording a reason)
    /// when another app is detected writing nutrition, to avoid double counts.
    public static var healthNutritionWriteEnabled: Bool {
        get { kv.bool(forKey: healthNutritionWriteKey) }
        set {
            kv.set(newValue, forKey: healthNutritionWriteKey)
            if newValue { healthNutritionAutoDisableReason = nil }
        }
    }

    /// Why the writer auto-disabled the toggle (e.g. "MyApp is already
    /// writing nutrition to Health") — surfaced in Settings. nil when the
    /// toggle hasn't been auto-disabled.
    public static var healthNutritionAutoDisableReason: String? {
        get { kv.string(forKey: healthNutritionAutoDisableKey) }
        set { kv.set(newValue, forKey: healthNutritionAutoDisableKey) }
    }

    // MARK: - Install Date + Feedback Prompt (#759)

    private static let installDateKey = "drift_install_date"
    private static let feedbackPromptSeenKey = "drift_feedback_prompt_seen"

    /// Epoch seconds when Drift was first launched on this device. Nil until
    /// `seedInstallDateIfNeeded()` runs (called from app launch). Used to gate
    /// the 7-day Feedback activation banner on the dashboard.
    public static var installDate: Date? {
        get {
            let v = kv.double(forKey: installDateKey)
            return v > 0 ? Date(timeIntervalSince1970: v) : nil
        }
        set {
            if let v = newValue {
                kv.set(v.timeIntervalSince1970, forKey: installDateKey)
            } else {
                kv.removeObject(forKey: installDateKey)
            }
        }
    }

    /// Seed `installDate` to `now` if unset. No-op if a value already exists.
    /// Called once from DriftApp launch so the install timestamp survives
    /// across app updates.
    public static func seedInstallDateIfNeeded(now: Date = Date()) {
        if kv.double(forKey: installDateKey) <= 0 {
            kv.set(now.timeIntervalSince1970, forKey: installDateKey)
        }
    }

    /// True once the user has tapped (or dismissed) the dashboard Feedback
    /// banner. Banner predicate uses this to suppress redisplay forever.
    public static var hasSeenFeedbackPrompt: Bool {
        get { kv.bool(forKey: feedbackPromptSeenKey) }
        set { kv.set(newValue, forKey: feedbackPromptSeenKey) }
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
