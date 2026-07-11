import Foundation
@testable import Drift
@testable import DriftCore
import Testing

// MARK: - Coach voice gate (field report 2026-07-10: "voice is always off")
// Voice in → voice out for the session; only an EXPLICIT speaker mute keeps a
// voice conversation silent; the session enable is never persisted (#937 —
// the old bug was writing the force-enable to Preferences).

@Suite(.serialized) @MainActor struct CoachVoiceGateTests {

    private func reset() {
        UserDefaults.standard.removeObject(forKey: "drift_coach_voice_enabled")
        UserDefaults.standard.removeObject(forKey: "drift_coach_voice_muted")
        UserDefaults.standard.removeObject(forKey: "drift_coach_talk_mode_enabled")
    }

    @Test func talkModeOnEnablesVoiceForSessionWithoutPersisting() {
        reset(); defer { reset() }
        let vm = AIChatViewModel()
        #expect(!vm.voiceOutputEnabled, "speaker starts off by default")
        vm.toggleTalkMode()
        #expect(vm.voiceOutputEnabled, "opening the voice surface must un-mute the coach")
        #expect(!Preferences.coachVoiceEnabled, "session enable must NOT persist (#937)")
        vm.toggleTalkMode()
    }

    @Test func explicitMuteWinsOverTalkMode() {
        reset(); defer { reset() }
        let vm = AIChatViewModel()
        vm.toggleVoiceOutput()   // explicit ON
        vm.toggleVoiceOutput()   // explicit OFF = mute
        #expect(Preferences.coachVoiceExplicitlyMuted)
        vm.toggleTalkMode()
        #expect(!vm.voiceOutputEnabled, "explicit mute keeps talk mode on captions")
        vm.toggleTalkMode()
    }

    @Test func speakerToggleRecordsExplicitIntentBothWays() {
        reset(); defer { reset() }
        let vm = AIChatViewModel()
        vm.toggleVoiceOutput()
        #expect(vm.voiceOutputEnabled && Preferences.coachVoiceEnabled)
        #expect(!Preferences.coachVoiceExplicitlyMuted, "explicit ON clears the mute")
        vm.toggleVoiceOutput()
        #expect(!vm.voiceOutputEnabled)
        #expect(Preferences.coachVoiceExplicitlyMuted, "explicit OFF records the mute")
    }
}
