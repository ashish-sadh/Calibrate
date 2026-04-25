import Foundation

/// Single registry for platform-bound adapters. The iOS Drift app installs
/// concrete impls on launch (`DriftPlatform.health = HealthKitService.shared`
/// etc.). Cross-platform services in DriftCore call through these accessors;
/// tests on macOS register stubs (or leave nil to fail-soft).
@MainActor
public enum DriftPlatform {
    public static var health: HealthDataProvider?
    public static var widget: WidgetRefresher?
}
