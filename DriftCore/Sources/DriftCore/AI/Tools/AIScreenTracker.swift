import Foundation
import Observation

/// Tracks which screen the user is currently viewing for context-aware AI responses.
@MainActor @Observable
public final class AIScreenTracker {
    public static let shared = AIScreenTracker()
    public var currentScreen: AIScreen = .dashboard {
        didSet {
            // On-device usage counter (never leaves the device) — every
            // screen the user lands on. See FeatureUsage.
            if oldValue != currentScreen { FeatureUsage.record("screen.\(currentScreen.rawValue)") }
        }
    }

    private init() {}
}
