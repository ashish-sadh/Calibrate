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

    func testStartInTextModeEntersTypingPhaseWithoutSpeech() async {
        // #869 — typed free-text ("Describe your meal") entry must NOT start
        // the speech stack (no second AVAudioSession owner); it lands the
        // user on the typing screen instead of .listening.
        let vm = VoiceLogViewModel()
        await vm.start(mode: .text)
        XCTAssertEqual(vm.phase, .typing)
        XCTAssertTrue(vm.transcript.isEmpty)
        XCTAssertTrue(vm.parsedItems.isEmpty)
    }

    func testSubmitTypedRoutesIntoTheMultiItemConfirmationCard() async {
        // #869 — typed text funnels through the SAME parse → confirmation
        // card the voice path uses. Force the FM kill-switch OFF so parse
        // takes the deterministic fallback (FM multi-item accuracy is
        // Tier-3, owned by #870); the assertion here is the WIRING: typed
        // input reaches .confirming with a confirmable row, NOT a dropped
        // single-row numeric form.
        let saved = Preferences.fmFoodIntentExtractEnabled
        Preferences.fmFoodIntentExtractEnabled = false
        defer { Preferences.fmFoodIntentExtractEnabled = saved }

        let vm = VoiceLogViewModel()
        await vm.start(mode: .text)
        await vm.submitTyped("dal, rice and two rotis")

        XCTAssertEqual(vm.phase, .confirming)
        XCTAssertGreaterThanOrEqual(vm.parsedItems.count, 1)
        XCTAssertEqual(vm.transcript, "dal, rice and two rotis")
    }

    func testSubmitTypedIgnoresBlankInput() async {
        // Guard: an all-whitespace draft must not advance past typing.
        let vm = VoiceLogViewModel()
        await vm.start(mode: .text)
        await vm.submitTyped("   ")
        XCTAssertEqual(vm.phase, .typing)
        XCTAssertTrue(vm.parsedItems.isEmpty)
    }

    // Note: the live speech start/stop cycle still requires SFSpeechRecognizer
    // + mic permission, and FM multi-item extraction requires iOS 26 with
    // Apple Intelligence — both device-only and covered by Tier-3 eval (#870).
}
