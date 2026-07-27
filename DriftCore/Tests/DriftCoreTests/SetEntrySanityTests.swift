import Testing
@testable import DriftCore

struct SetEntrySanityTests {

    @Test func normalSetsStaySilent() {
        // Realistic entries never nag.
        #expect(SetEntrySanity.warning(weightLbs: 98, reps: 8, isDuration: false,
                                       previousTopWeightLbs: 98, unit: .lbs) == nil)
        #expect(SetEntrySanity.warning(weightLbs: 135, reps: 12, isDuration: false,
                                       previousTopWeightLbs: 115, unit: .lbs) == nil)
        // First-timer with no history, sane weight.
        #expect(SetEntrySanity.warning(weightLbs: 225, reps: 5, isDuration: false,
                                       previousTopWeightLbs: nil, unit: .lbs) == nil)
    }

    @Test func extraDigitWeightJumpWarns() {
        // 98 → 980: the classic fat-finger.
        #expect(SetEntrySanity.warning(weightLbs: 980, reps: 8, isDuration: false,
                                       previousTopWeightLbs: 98, unit: .lbs) != nil)
    }

    @Test func absoluteWeightCeilingWarnsEvenWithoutHistory() {
        #expect(SetEntrySanity.warning(weightLbs: 2000, reps: 3, isDuration: false,
                                       previousTopWeightLbs: nil, unit: .lbs) != nil)
    }

    @Test func lightAccessoryJumpStaysSilent() {
        // 5 → 15 lb triples but is under the 100 lb floor — no nag.
        #expect(SetEntrySanity.warning(weightLbs: 15, reps: 12, isDuration: false,
                                       previousTopWeightLbs: 5, unit: .lbs) == nil)
    }

    @Test func repsTypoWarns() {
        // 8 → 88 is under the ceiling and stays silent (conservative), but a
        // truly impossible count trips it.
        #expect(SetEntrySanity.warning(weightLbs: 45, reps: 8, isDuration: false,
                                       previousTopWeightLbs: 45, unit: .lbs) == nil)
        #expect(SetEntrySanity.warning(weightLbs: 45, reps: 120, isDuration: false,
                                       previousTopWeightLbs: 45, unit: .lbs) != nil)
    }

    @Test func durationUsesSecondsCeilingNotRepsCeiling() {
        // 120 "reps" is fine when it's 120 seconds of a plank.
        #expect(SetEntrySanity.warning(weightLbs: nil, reps: 120, isDuration: true,
                                       previousTopWeightLbs: nil, unit: .lbs) == nil)
        #expect(SetEntrySanity.warning(weightLbs: nil, reps: 6000, isDuration: true,
                                       previousTopWeightLbs: nil, unit: .lbs) != nil)
    }

    @Test func messageReadsInUserUnit() {
        // A kg user sees kg in the prompt, not the stored lbs.
        let msg = SetEntrySanity.warning(weightLbs: 2200, reps: 3, isDuration: false,
                                         previousTopWeightLbs: nil, unit: .kg)
        #expect(msg?.contains("kg") == true)
        #expect(msg?.contains("lbs") == false)
    }
}
