import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Single registry for platform-bound adapters. The iOS Drift app installs
/// concrete impls on launch (`DriftPlatform.health = HealthKitService.shared`
/// etc.). Cross-platform services in DriftCore call through these accessors;
/// tests on macOS register stubs (or leave nil to fail-soft).
@MainActor
public enum DriftPlatform {
    public static var health: HealthDataProvider?
    public static var widget: WidgetRefresher?
    /// Apple Health nutrition write-back (#934). nil on macOS/tests = no-op.
    public static var nutritionWriter: HealthNutritionWriter?
    /// Photo-library image-in seam (#1128). iOS installs a PHPicker wrapper,
    /// Android an Activity-result facade wrapper. nil on macOS/tests =
    /// fail-soft (capture entry points hide or no-op, matching `health`).
    public static var imagePicker: ImagePicking?
    /// Platform-secure store for the sharing auth session (iOS Keychain /
    /// Android EncryptedSharedPreferences). nil = fall back to the SQLite
    /// `sync_session` table (durable on both platforms, less protected).
    public static var secureStore: SecureTokenStore?

    /// Key–value persistence seam (#1108). Defaults to `UserDefaultsKVStore`,
    /// so iOS/macOS behaviour is unchanged (backed by `UserDefaults.standard`).
    /// The Android app installs a SQLite-backed `DbKeyValueStore` in its launch
    /// `onInit`, because Skip Fuse's SharedPreferences-backed `UserDefaults`
    /// never durably persists (settings + the active workout would be lost on
    /// process death).
    ///
    /// `nonisolated(unsafe)`: the non-isolated `Preferences` accessors read this
    /// synchronously from background services (off the main actor). The value
    /// is a `Sendable` store written exactly once at launch, before any read —
    /// so the "unsafe" opt-out of actor isolation is sound.
    nonisolated(unsafe) public static var keyValueStore: KeyValueStore = UserDefaultsKVStore()

    /// HTTP transport seam for ALL of DriftCore's networking (#1136, widened in
    /// #1194). Defaults to `URLSession.shared`, so iOS/macOS behaviour is
    /// unchanged. The Android app installs `AndroidHTTPSession` (OkHttp facade)
    /// in its launch `onInit`, because swift-corelibs-foundation's URLSession
    /// parks non-cancellably on Skip — a parked call is worse than a failed one
    /// (no error, no timeout, no fallback, just a spinner forever).
    ///
    /// Anything in DriftCore that talks to the network goes through here.
    /// Reaching for `URLSession.shared` directly is a regression: it works on
    /// iOS and hangs on Android, which is the failure mode that left sharing
    /// dead on Android from the day it shipped.
    ///
    /// `nonisolated(unsafe)`: same rationale as `keyValueStore` — a `Sendable`
    /// value written exactly once at launch, before any read, then read
    /// off-main at the construction sites.
    nonisolated(unsafe) public static var httpSession: any HTTPDataSession = URLSession.shared

    /// Local-notification seam (#1162). iOS installs a wrapper around
    /// `UNUserNotificationCenter`; Android installs one around
    /// `NotificationManager`. nil = alerts are silently skipped, which is the
    /// right fail-soft: the Today-screen signals still work, and a missing
    /// notifier must never break a poll.
    ///
    /// `nonisolated(unsafe)` — same rationale as `keyValueStore`: written once
    /// at launch, read from the background poll off the main actor.
    nonisolated(unsafe) public static var notifier: (any LocalNotifier)? = nil
}
