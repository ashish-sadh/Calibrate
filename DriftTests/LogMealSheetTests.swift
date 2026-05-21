import XCTest
import SwiftUI
@testable import Drift
@testable import DriftCore

/// V7 Phase 5 — covers the LogMealMode enum + the four sub-views the
/// segmented sheet renders. Doesn't exercise the live SFSpeechRecognizer
/// path (that needs mic permission); the VoiceLogSheet view-model is
/// covered separately.
@MainActor
final class LogMealSheetTests: XCTestCase {

    func testLogMealModeRoundTripsThroughRawValue() {
        for mode in LogMealMode.allCases {
            let restored = LogMealMode(rawValue: mode.rawValue)
            XCTAssertEqual(restored, mode)
        }
    }

    func testLogMealModeLabelsAreNonEmpty() {
        for mode in LogMealMode.allCases {
            XCTAssertFalse(mode.label.isEmpty)
            XCTAssertFalse(mode.icon.isEmpty)
        }
    }

    func testSheetConstructsAtEveryMode() {
        for mode in LogMealMode.allCases {
            let sheet = LogMealSheet(initialMode: mode)
            _ = sheet.body
        }
    }

    func testNotificationNameIsStable() {
        // ContentView listens on this name string. Renaming the rawValue
        // would silently break the Dashboard chip wire-up — pin it here.
        XCTAssertEqual(Notification.Name.openLogMeal.rawValue, "drift.openLogMeal")
    }
}

@MainActor
final class VoiceLogViewModelTests: XCTestCase {

    func testInitialPhaseIsListening() {
        let vm = VoiceLogViewModel()
        XCTAssertEqual(vm.phase, .listening)
        XCTAssertTrue(vm.transcript.isEmpty)
        XCTAssertTrue(vm.parsedItems.isEmpty)
    }

    // Note: full start/stop/parse cycle requires SFSpeechRecognizer +
    // permission grant + (for FM extractor) iOS 26 with Apple
    // Intelligence enabled. Those are device-only; the VM smoke test
    // above is the most we can assert in the iOS test target.
}
