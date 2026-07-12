import Foundation
@testable import Drift
@testable import DriftCore
import Testing

// MARK: - Coach voice gate (operator call 2026-07-11)
// The speaker toggle is the SINGLE source of truth for spoken replies —
// default ON, persisted on explicit toggle, never overridden by talk mode or
// mic turns. The v3 migration lifts the #968 blanket-false so shipped
// installs pick up the new default.

@Suite(.serialized) @MainActor struct CoachVoiceGateTests {

    private func reset() {
        for key in ["drift_coach_voice_enabled", "drift_coach_voice_v2_migrated",
                    "drift_coach_voice_v3_migrated", "drift_coach_talk_mode_enabled"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @Test func speakerDefaultsOn() {
        reset(); defer { reset() }
        #expect(Preferences.coachVoiceEnabled, "a voice-first coach must not ship mute")
        let vm = AIChatViewModel()
        #expect(vm.voiceOutputEnabled)
    }

    @Test func v3MigrationLiftsTheV2BlanketFalse() {
        reset(); defer { reset() }
        // A field install after #968: v2 stamped false onto everyone.
        UserDefaults.standard.set(false, forKey: "drift_coach_voice_enabled")
        UserDefaults.standard.set(true, forKey: "drift_coach_voice_v2_migrated")
        Preferences.migrateCoachVoiceIfNeeded()
        #expect(Preferences.coachVoiceEnabled, "v3 clears the migration-stamped false")
    }

    @Test func migrationRunsOnceSoExplicitOffSticks() {
        reset(); defer { reset() }
        Preferences.migrateCoachVoiceIfNeeded()
        let vm = AIChatViewModel()
        vm.toggleVoiceOutput()   // explicit OFF
        #expect(!Preferences.coachVoiceEnabled)
        Preferences.migrateCoachVoiceIfNeeded()   // next launch
        #expect(!Preferences.coachVoiceEnabled, "a real user choice must survive relaunch")
    }

    @Test func talkModeNeverTouchesTheSpeakerSetting() {
        reset(); defer { reset() }
        let vm = AIChatViewModel()
        vm.toggleVoiceOutput()   // explicit OFF
        vm.toggleTalkMode()
        #expect(!vm.voiceOutputEnabled, "talk mode with speaker off = captions (#937)")
        #expect(!Preferences.coachVoiceEnabled)
        vm.toggleTalkMode()
    }
}
