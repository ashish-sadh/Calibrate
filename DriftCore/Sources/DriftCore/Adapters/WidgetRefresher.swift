import Foundation

/// Adapter for triggering home-screen widget refresh. iOS Drift app provides
/// the concrete impl backed by `WidgetCenter`; tests inject a no-op.
public protocol WidgetRefresher: Sendable {
    @MainActor func refresh()
}
