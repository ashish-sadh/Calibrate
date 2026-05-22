import XCTest
import SwiftUI
@testable import Drift
import DriftCore

/// Tier-1 tests for `BodySummaryCardsRow` payload factories — the pure mappers
/// that build WEIGHT / SLEEP / READINESS card data from raw viewmodel values.
/// Locks the empty-state copy, the goal-aware color flip on WEIGHT, and the
/// non-goal-aware behavior on SLEEP / READINESS.
@MainActor
final class BodySummaryCardsRowTests: XCTestCase {

    private var savedWeightUnit: WeightUnit = .lbs

    override func setUp() {
        super.setUp()
        savedWeightUnit = Preferences.weightUnit
        Preferences.weightUnit = .lbs
    }

    override func tearDown() {
        Preferences.weightUnit = savedWeightUnit
        super.tearDown()
    }

    // MARK: - Empty-state copy (pinned by #821 Done-When criterion 2)

    func testWeightEmptyTextMatchesSpec() {
        XCTAssertEqual(BodySummaryCardsRow.weightEmptyText, "Log your weight to track progress")
    }

    func testSleepEmptyTextMatchesSpec() {
        XCTAssertEqual(BodySummaryCardsRow.sleepEmptyText, "Connect Apple Health for sleep data")
    }

    func testReadinessEmptyTextMatchesSpec() {
        XCTAssertEqual(BodySummaryCardsRow.readinessEmptyText, "Connect Whoop or log a manual score")
    }

    // MARK: - WEIGHT card

    func testWeightPayloadWithNoWeightUsesEmptyState() {
        let p = BodySummaryCardsRow.weightPayload(weightKg: nil, weeklyRateKg: nil, goalDirection: .lose)
        XCTAssertEqual(p.label, "WEIGHT")
        XCTAssertNil(p.value)
        XCTAssertEqual(p.emptyText, "Log your weight to track progress")
    }

    func testWeightPayloadGuardsNegativeKg() {
        let p = BodySummaryCardsRow.weightPayload(weightKg: -75.0, weeklyRateKg: nil, goalDirection: .lose)
        XCTAssertNil(p.value, "Corrupt negative weight renders the empty state, not '-165 lbs'")
    }

    func testWeightPayloadGuardsNaN() {
        let p = BodySummaryCardsRow.weightPayload(weightKg: .nan, weeklyRateKg: nil, goalDirection: .lose)
        XCTAssertNil(p.value)
    }

    func testWeightPayloadConvertsKgToLbs() {
        Preferences.weightUnit = .lbs
        let p = BodySummaryCardsRow.weightPayload(weightKg: 75.0, weeklyRateKg: nil, goalDirection: .lose)
        XCTAssertTrue(p.value?.hasPrefix("165.") ?? false,
                      "75kg renders as ~165.x lbs; got \(p.value ?? "nil")")
        XCTAssertEqual(p.unit, "lbs")
    }

    func testWeightPayloadRespectsKgPreference() {
        Preferences.weightUnit = .kg
        let p = BodySummaryCardsRow.weightPayload(weightKg: 75.0, weeklyRateKg: 0.5, goalDirection: .lose)
        XCTAssertEqual(p.value, "75.0")
        XCTAssertEqual(p.unit, "kg")
        XCTAssertEqual(p.detail, "+0.50 kg/wk")
    }

    func testWeightPayloadFormatsNegativeRateWithMinus() {
        Preferences.weightUnit = .kg
        let p = BodySummaryCardsRow.weightPayload(weightKg: 70.0, weeklyRateKg: -0.30, goalDirection: .lose)
        XCTAssertEqual(p.detail, "-0.30 kg/wk")
    }

    func testWeightPayloadOmitsDetailWhenRateIsZero() {
        let p = BodySummaryCardsRow.weightPayload(weightKg: 75.0, weeklyRateKg: 0.0, goalDirection: .lose)
        XCTAssertNil(p.detail, "Zero rate has no weekly delta worth surfacing")
    }

    // MARK: - Goal-aware color (the heart of #821 — green if aligned, red if against)

    func testWeightColorIsGreenWhenLosingAndRateIsNegative() {
        let color = BodySummaryCardsRow.goalAlignedColor(weeklyRateKg: -0.30, goalDirection: .lose)
        XCTAssertEqual(color, Theme.deficit, "Losing goal + negative rate = aligned (green)")
    }

    func testWeightColorIsRedWhenLosingButRateIsPositive() {
        let color = BodySummaryCardsRow.goalAlignedColor(weeklyRateKg: 0.40, goalDirection: .lose)
        XCTAssertEqual(color, Theme.surplus, "Losing goal + gaining = against (red)")
    }

    func testWeightColorIsGreenWhenGainingAndRateIsPositive() {
        let color = BodySummaryCardsRow.goalAlignedColor(weeklyRateKg: 0.30, goalDirection: .gain)
        XCTAssertEqual(color, Theme.deficit, "Gain goal + positive rate = aligned (green)")
    }

    func testWeightColorIsRedWhenGainingButRateIsNegative() {
        let color = BodySummaryCardsRow.goalAlignedColor(weeklyRateKg: -0.30, goalDirection: .gain)
        XCTAssertEqual(color, Theme.surplus, "Gain goal + losing = against (red)")
    }

    func testWeightColorIsNeutralOnMaintainDirection() {
        let color = BodySummaryCardsRow.goalAlignedColor(weeklyRateKg: -0.30, goalDirection: .maintain)
        XCTAssertEqual(color, Theme.textPrimary,
                       "Maintain goal doesn't have a 'good' direction; stay neutral")
    }

    func testWeightColorIsNeutralWhenNoGoalSet() {
        let color = BodySummaryCardsRow.goalAlignedColor(weeklyRateKg: -0.30, goalDirection: .none)
        XCTAssertEqual(color, Theme.textPrimary)
    }

    func testWeightColorIsNeutralWhenRateIsNil() {
        let color = BodySummaryCardsRow.goalAlignedColor(weeklyRateKg: nil, goalDirection: .lose)
        XCTAssertEqual(color, Theme.textPrimary, "Can't be aligned or against if there's no rate")
    }

    func testWeightColorIsNeutralWhenRateIsNonFinite() {
        let color = BodySummaryCardsRow.goalAlignedColor(weeklyRateKg: .nan, goalDirection: .lose)
        XCTAssertEqual(color, Theme.textPrimary, "NaN can't color the value")
    }

    // MARK: - SLEEP card

    func testSleepPayloadWithZeroHoursUsesEmptyState() {
        let p = BodySummaryCardsRow.sleepPayload(hours: 0)
        XCTAssertEqual(p.label, "SLEEP")
        XCTAssertNil(p.value)
        XCTAssertEqual(p.emptyText, "Connect Apple Health for sleep data")
    }

    func testSleepPayloadFormatsHoursToOneDecimal() {
        let p = BodySummaryCardsRow.sleepPayload(hours: 7.4)
        XCTAssertEqual(p.value, "7.4")
        XCTAssertEqual(p.unit, "h")
        XCTAssertEqual(p.detail, "last night")
    }

    func testSleepPayloadGuardsNonFiniteHours() {
        XCTAssertNil(BodySummaryCardsRow.sleepPayload(hours: .nan).value)
        XCTAssertNil(BodySummaryCardsRow.sleepPayload(hours: .infinity).value)
    }

    func testSleepPayloadValueColorStaysNeutral() {
        // SLEEP is not goal-tracked — value stays primary regardless of hours.
        let great = BodySummaryCardsRow.sleepPayload(hours: 9.0)
        let bad = BodySummaryCardsRow.sleepPayload(hours: 3.0)
        XCTAssertEqual(great.valueColor, Theme.textPrimary)
        XCTAssertEqual(bad.valueColor, Theme.textPrimary)
    }

    // MARK: - READINESS card

    func testReadinessPayloadWithZeroScoreUsesEmptyState() {
        let p = BodySummaryCardsRow.readinessPayload(recoveryScore: 0, hrvMs: 0)
        XCTAssertEqual(p.label, "READINESS")
        XCTAssertNil(p.value)
        XCTAssertEqual(p.emptyText, "Connect Whoop or log a manual score")
    }

    func testReadinessPayloadWithScoreAndHRVShowsHRVDetail() {
        let p = BodySummaryCardsRow.readinessPayload(recoveryScore: 82, hrvMs: 65)
        XCTAssertEqual(p.value, "82")
        XCTAssertEqual(p.detail, "65ms HRV")
    }

    func testReadinessPayloadWithScoreButNoHRVHasNilDetail() {
        let p = BodySummaryCardsRow.readinessPayload(recoveryScore: 50, hrvMs: 0)
        XCTAssertEqual(p.value, "50")
        XCTAssertNil(p.detail)
    }

    func testReadinessPayloadValueColorStaysNeutral() {
        // READINESS not goal-tracked either.
        let p = BodySummaryCardsRow.readinessPayload(recoveryScore: 82, hrvMs: 65)
        XCTAssertEqual(p.valueColor, Theme.textPrimary)
    }

    // MARK: - Bundle factory

    func testPayloadsBundleBuildsAllThreeCards() {
        let bundle = BodySummaryCardsRow.payloads(
            weightKg: 75.0, weeklyRateKg: -0.30,
            sleepHours: 7.4,
            recoveryScore: 82, hrvMs: 65,
            goalDirection: .lose
        )
        XCTAssertEqual(bundle.weight.label, "WEIGHT")
        XCTAssertEqual(bundle.sleep.label, "SLEEP")
        XCTAssertEqual(bundle.readiness.label, "READINESS")
        XCTAssertNotNil(bundle.weight.value)
        XCTAssertNotNil(bundle.sleep.value)
        XCTAssertNotNil(bundle.readiness.value)
    }

    func testPayloadsBundleAllEmpty() {
        let bundle = BodySummaryCardsRow.payloads(
            weightKg: nil, weeklyRateKg: nil,
            sleepHours: 0,
            recoveryScore: 0, hrvMs: 0,
            goalDirection: .none
        )
        XCTAssertNil(bundle.weight.value)
        XCTAssertNil(bundle.sleep.value)
        XCTAssertNil(bundle.readiness.value)
    }

    // MARK: - View construction smoke

    func testBodySummaryCardsRowConstructsForAllShapes() {
        let bundle = BodySummaryCardsRow.payloads(
            weightKg: 75.0, weeklyRateKg: -0.30,
            sleepHours: 7.4,
            recoveryScore: 82, hrvMs: 65,
            goalDirection: .lose
        )
        let view = BodySummaryCardsRow(payloads: bundle, onTapBody: {})
        XCTAssertNotNil(view)
    }
}
