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

    func testInitialPhaseIsTyping() {
        // #935: the merged Describe screen opens on the typed field; the
        // mic is opt-in (beginListening) — never auto-starts the speech stack.
        let vm = VoiceLogViewModel()
        vm.start()
        XCTAssertEqual(vm.phase, .typing)
        XCTAssertTrue(vm.transcript.isEmpty)
        XCTAssertTrue(vm.reviewItems.isEmpty)
    }

    func testStartEntersTypingPhaseWithoutSpeech() async {
        // #869/#935 — starting the Describe screen must NOT start the speech
        // stack (no second AVAudioSession owner); the mic is a button.
        let vm = VoiceLogViewModel()
        vm.start()
        XCTAssertEqual(vm.phase, .typing)
        XCTAssertTrue(vm.transcript.isEmpty)
        XCTAssertTrue(vm.reviewItems.isEmpty)
    }

    func testSubmitTypedRoutesIntoTheMultiItemConfirmationCard() async {
        // #869 — typed text funnels through the SAME parse → confirmation
        // card the voice path uses. Force the FM kill-switch OFF so parse
        // takes the deterministic fallback (FM multi-item accuracy is
        // Tier-3, owned by #870); the assertion here is the WIRING: typed
        // input reaches .confirming with a confirmable row, NOT a dropped
        // single-row numeric form.
        let savedFM = Preferences.fmFoodIntentExtractEnabled
        let savedCloud = Preferences.coachCloudFoodParseEnabled
        Preferences.fmFoodIntentExtractEnabled = false
        Preferences.coachCloudFoodParseEnabled = false   // offline: no Nebius call in tests
        defer {
            Preferences.fmFoodIntentExtractEnabled = savedFM
            Preferences.coachCloudFoodParseEnabled = savedCloud
        }

        let vm = VoiceLogViewModel()
        vm.start()
        await vm.submitTyped("dal, rice and two rotis")

        XCTAssertEqual(vm.phase, .confirming)
        XCTAssertGreaterThanOrEqual(vm.reviewItems.count, 1)
        XCTAssertEqual(vm.transcript, "dal, rice and two rotis")
    }

    func testSubmitTypedIgnoresBlankInput() async {
        // Guard: an all-whitespace draft must not advance past typing.
        let vm = VoiceLogViewModel()
        vm.start()
        await vm.submitTyped("   ")
        XCTAssertEqual(vm.phase, .typing)
        XCTAssertTrue(vm.reviewItems.isEmpty)
    }

    // Note: the live speech start/stop cycle still requires SFSpeechRecognizer
    // + mic permission, and FM multi-item extraction requires iOS 26 with
    // Apple Intelligence — both device-only and covered by Tier-3 eval (#870).
}

// MARK: - #935: Voice + Text merged into one Describe method

extension LogMealSheetTests {
    func testFourSegmentsAndNoVoiceMode() {
        XCTAssertEqual(LogMealMode.allCases.count, 4, "Recent · Search · Describe · Snap")
        XCTAssertEqual(LogMealMode.allCases, [.recent, .search, .describe, .snap])
        XCTAssertNil(LogMealMode(rawValue: "voice"), "the separate Voice segment is gone")
        XCTAssertEqual(LogMealMode.describe.label, "Describe")
    }
}
