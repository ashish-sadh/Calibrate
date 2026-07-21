@testable import DriftCore
import Testing

/// Tier 0 — deterministic boundaries for health-term transcription repairs.
@Suite struct VoiceTranscriptionPostFixerBoundaryTests {
    @Test func glp1MedicationMisrecognitionsAreRewritten() {
        #expect(VoiceTranscriptionPostFixer.fix("o zen pick injection") == "ozempic injection")
        #expect(VoiceTranscriptionPostFixer.fix("we go v dose") == "wegovy dose")
        #expect(VoiceTranscriptionPostFixer.fix("mount jarrow injection") == "mounjaro injection")
    }

    @Test func unambiguousRulesAreCaseInsensitiveButWordBounded() {
        #expect(VoiceTranscriptionPostFixer.fix("BURBERRY supplement") == "berberine supplement")
        #expect(VoiceTranscriptionPostFixer.fix("Burberrys are shrubs") == "Burberrys are shrubs")
    }

    @Test func collagenRepairRequiresAdjacentSupplementContext() {
        #expect(VoiceTranscriptionPostFixer.fix("colleague in peptide blend") == "collagen peptide blend")
        #expect(VoiceTranscriptionPostFixer.fix("colleague in the office") == "colleague in the office")
    }

    @Test func vitaminD3RepairRequiresFollowingDosage() {
        #expect(VoiceTranscriptionPostFixer.fix("vitamin d three 2000 IU") == "vitamin d3 2000 IU")
        #expect(VoiceTranscriptionPostFixer.fix("vitamin d three supplement") == "vitamin d three supplement")
    }

    @Test func omega3RepairRecognizesEachGuardAndRejectsPlainProse() {
        #expect(VoiceTranscriptionPostFixer.fix("omega three fish oil") == "omega-3 fish oil")
        #expect(VoiceTranscriptionPostFixer.fix("omega three capsule") == "omega-3 capsule")
        #expect(VoiceTranscriptionPostFixer.fix("omega three 1000mg") == "omega-3 1000mg")
        #expect(VoiceTranscriptionPostFixer.fix("omega three fatty acid") == "omega three fatty acid")
    }
}
