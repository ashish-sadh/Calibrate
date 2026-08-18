import Foundation
@testable import DriftCore
import Testing

// Tier-0: pure. No DB, no clock dependence, no LLM.
//
// `GoalDirection` was lifted out of `Drift/Views/BodySummaryCardsRow.swift` so
// Android's Today WEIGHT card could colour itself by the SAME rule as the
// iPhone's (#1202/#1203). Before the lift the rule existed only inside an iOS
// view; these pin it as a contract both platforms now read.

// MARK: - derive

private func goal(target: Double, start: Double) -> WeightGoal {
    WeightGoal(targetWeightKg: target, monthsToAchieve: 6,
               startDate: currentGoalStartDate(), startWeightKg: start)
}

@Test func deriveWithNoGoalIsNone() {
    #expect(GoalDirection.derive(goal: nil, currentWeightKg: 80) == .none)
    #expect(GoalDirection.derive(goal: nil, currentWeightKg: nil) == .none)
}

@Test func deriveAboveTargetIsLose() {
    #expect(GoalDirection.derive(goal: goal(target: 70, start: 85), currentWeightKg: 80) == .lose)
}

@Test func deriveBelowTargetIsGain() {
    #expect(GoalDirection.derive(goal: goal(target: 80, start: 65), currentWeightKg: 70) == .gain)
}

/// Within 100g of target reads as maintenance, either side — this is the case
/// neither pre-existing enum in DriftCore could express, and the reason the
/// lift got its own type instead of reusing `BriefingAggregator`'s.
@Test func deriveAtTargetIsMaintain() {
    let g = goal(target: 70, start: 85)
    #expect(GoalDirection.derive(goal: g, currentWeightKg: 70) == .maintain)
    #expect(GoalDirection.derive(goal: g, currentWeightKg: 70.09) == .maintain)
    #expect(GoalDirection.derive(goal: g, currentWeightKg: 69.91) == .maintain)
    // …and 100g out is a real direction again.
    #expect(GoalDirection.derive(goal: g, currentWeightKg: 70.2) == .lose)
    #expect(GoalDirection.derive(goal: g, currentWeightKg: 69.8) == .gain)
}

/// A goal with no weigh-ins yet still reads as a direction — the start weight
/// stands in, so the card is never mysteriously neutral on a fresh install.
@Test func deriveWithNoCurrentWeightFallsBackToStartWeight() {
    #expect(GoalDirection.derive(goal: goal(target: 70, start: 85), currentWeightKg: nil) == .lose)
    #expect(GoalDirection.derive(goal: goal(target: 80, start: 65), currentWeightKg: nil) == .gain)
    #expect(GoalDirection.derive(goal: goal(target: 70, start: 70), currentWeightKg: nil) == .maintain)
}

// MARK: - alignment

@Test func losingAlignsWithADownwardRate() {
    #expect(GoalDirection.lose.alignment(ofWeeklyRateKg: -0.4) == .aligned)
    #expect(GoalDirection.lose.alignment(ofWeeklyRateKg: 0.4) == .against)
}

@Test func gainingAlignsWithAnUpwardRate() {
    #expect(GoalDirection.gain.alignment(ofWeeklyRateKg: 0.4) == .aligned)
    #expect(GoalDirection.gain.alignment(ofWeeklyRateKg: -0.4) == .against)
}

/// Maintenance and no-goal are never "good" or "bad" — drifting either way off
/// a maintenance target is just drift, and with no goal there is nothing to be
/// aligned with.
@Test func maintainAndNoneAreAlwaysNeutral() {
    for rate in [-0.9, -0.2, 0.2, 0.9] {
        #expect(GoalDirection.maintain.alignment(ofWeeklyRateKg: rate) == .neutral)
        #expect(GoalDirection.none.alignment(ofWeeklyRateKg: rate) == .neutral)
    }
}

/// Missing / non-finite / effectively-zero rates are neutral for EVERY
/// direction — the card must not flip green or red off measurement noise.
@Test func unusableRatesAreNeutral() {
    let rates: [Double?] = [nil, 0, 0.0005, -0.0005, .nan, .infinity, -.infinity]
    for direction in [GoalDirection.lose, .gain, .maintain, .none] {
        for rate in rates {
            #expect(direction.alignment(ofWeeklyRateKg: rate) == .neutral,
                    "\(direction) with rate \(rate as Any) must be neutral")
        }
    }
    // The threshold is exclusive-above 0.001, so just past it does register.
    #expect(GoalDirection.lose.alignment(ofWeeklyRateKg: -0.002) == .aligned)
}

// MARK: - weeklyRateLine

@Test func weeklyRateLineSignsAndRoundsToTwoDecimals() {
    #expect(WeightUnit.kg.weeklyRateLine(fromKg: -0.35) == "-0.35 kg/wk")
    #expect(WeightUnit.kg.weeklyRateLine(fromKg: 0.4) == "+0.40 kg/wk")
    #expect(WeightUnit.kg.weeklyRateLine(fromKg: -0.126) == "-0.13 kg/wk")
}

@Test func weeklyRateLineConvertsToTheUsersUnit() {
    // -0.5 kg/wk ≈ -1.10 lbs/wk.
    #expect(WeightUnit.lbs.weeklyRateLine(fromKg: -0.5) == "-1.10 lbs/wk")
    #expect(WeightUnit.lbs.weeklyRateLine(fromKg: 0.9072) == "+2.00 lbs/wk")
}

/// No caption at all rather than a "+0.00/wk" that reads like a measurement —
/// same nil set the colour rule treats as neutral.
@Test func weeklyRateLineIsNilWithoutAUsableRate() {
    for unit in WeightUnit.allCases {
        #expect(unit.weeklyRateLine(fromKg: nil) == nil)
        #expect(unit.weeklyRateLine(fromKg: 0) == nil)
        #expect(unit.weeklyRateLine(fromKg: 0.0005) == nil)
        #expect(unit.weeklyRateLine(fromKg: -0.0005) == nil)
        #expect(unit.weeklyRateLine(fromKg: .nan) == nil)
        #expect(unit.weeklyRateLine(fromKg: .infinity) == nil)
    }
}
