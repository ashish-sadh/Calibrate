import Foundation
import Observation

/// Tracks which screen the user is currently viewing for context-aware AI responses.
@MainActor @Observable
public final class AIScreenTracker {
    public static let shared = AIScreenTracker()
    public var currentScreen: AIScreen = .dashboard {
        didSet {
            // Usage counter for every screen the user lands on — routes to
            // the anonymous, opt-out telemetry pipeline (ships to the backend
            // in batches since 2026-07-28). See FeatureUsage.
            if oldValue != currentScreen { FeatureUsage.record("screen.\(currentScreen.rawValue)") }
        }
    }

    private init() {}
}
