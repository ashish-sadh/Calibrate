import Foundation

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
    /// Platform-secure store for the sharing auth session (iOS Keychain /
    /// Android EncryptedSharedPreferences). nil = fall back to the SQLite
    /// `sync_session` table (durable on both platforms, less protected).
    public static var secureStore: SecureTokenStore?
}
