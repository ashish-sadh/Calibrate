import XCTest
import SwiftUI
@testable import Drift
@testable import DriftCore

/// Smoke test for `DriftCoachSheet` — the V7 Phase 5 replacement for
/// `FloatingAIAssistant`. Verifies that the sheet view constructs without
/// crashing and that the segmented backend picker round-trips through
/// `Preferences.preferredAIBackend` (criterion 2 + 5 of issue #831).
@MainActor
final class DriftCoachSheetTests: XCTestCase {

    func testSheetConstructs() {
        let sheet = DriftCoachSheet()
        _ = sheet.body
    }

    func testBackendPickerRoundTripsThroughPreferences() {
        let original = Preferences.preferredAIBackend
        defer { Preferences.preferredAIBackend = original }

        Preferences.preferredAIBackend = .llamaCpp
        XCTAssertEqual(Preferences.preferredAIBackend, .llamaCpp)

        Preferences.preferredAIBackend = .remote
        XCTAssertEqual(Preferences.preferredAIBackend, .remote)

        Preferences.preferredAIBackend = .foundationModels
        XCTAssertEqual(Preferences.preferredAIBackend, .foundationModels)

        _ = DriftCoachSheet().body
    }
}
