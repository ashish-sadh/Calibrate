import Foundation
import Testing
@testable import DriftCore

/// Tier-0 gate for the milestone rule extracted from `WeightViewModel.addWeight`
/// so iOS and Android celebrate the same weigh-ins (#1143). The rule is
/// goal-aware: losing celebrates a new minimum, gaining a new maximum, and an
/// empty history never celebrates (the FIRST weigh-in is not a milestone).
struct WeightMilestoneTests {

    @Test func newLowFiresWhenLosing() {
        let msg = WeightMilestone.message(newWeightKg: 79.4, existingWeightsKg: [82.0, 80.5, 81.2],
                                          isLosing: true, unit: .kg)
        #expect(msg == "New Low! 79.4 kg")
    }

    @Test func noMilestoneWhenLosingAndWeightIsNotANewMinimum() {
        #expect(WeightMilestone.message(newWeightKg: 81.0, existingWeightsKg: [82.0, 80.5],
                                        isLosing: true, unit: .kg) == nil)
    }

    @Test func equallingTheCurrentMinimumIsNotAMilestone() {
        #expect(WeightMilestone.message(newWeightKg: 80.5, existingWeightsKg: [82.0, 80.5],
                                        isLosing: true, unit: .kg) == nil)
    }

    @Test func newHighFiresWhenGaining() {
        let msg = WeightMilestone.message(newWeightKg: 84.2, existingWeightsKg: [82.0, 83.5],
                                          isLosing: false, unit: .kg)
        #expect(msg == "New High! 84.2 kg")
    }

    @Test func noMilestoneWhenGainingAndWeightIsNotANewMaximum() {
        #expect(WeightMilestone.message(newWeightKg: 83.0, existingWeightsKg: [82.0, 83.5],
                                        isLosing: false, unit: .kg) == nil)
    }

    /// A new low while GAINING (and a new high while losing) is progress in the
    /// wrong direction — never celebrated.
    @Test func wrongDirectionExtremeIsSilent() {
        #expect(WeightMilestone.message(newWeightKg: 70.0, existingWeightsKg: [82.0],
                                        isLosing: false, unit: .kg) == nil)
        #expect(WeightMilestone.message(newWeightKg: 95.0, existingWeightsKg: [82.0],
                                        isLosing: true, unit: .kg) == nil)
    }

    @Test func emptyHistoryNeverFires() {
        #expect(WeightMilestone.message(newWeightKg: 60.0, existingWeightsKg: [],
                                        isLosing: true, unit: .kg) == nil)
        #expect(WeightMilestone.message(newWeightKg: 60.0, existingWeightsKg: [],
                                        isLosing: false, unit: .kg) == nil)
    }

    /// The message is formatted in the user's display unit, not storage kg.
    @Test func lbsUsersSeeLbs() {
        let msg = WeightMilestone.message(newWeightKg: 79.4, existingWeightsKg: [82.0],
                                          isLosing: true, unit: .lbs)
        #expect(msg == "New Low! 175.0 lbs")
    }
}
