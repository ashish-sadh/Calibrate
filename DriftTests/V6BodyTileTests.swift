import XCTest
@testable import Drift
import DriftCore

/// Tier-1 tests for `V6BodyTile` — the V6 Dashboard body strip (Weight / Sleep
/// / Readiness). Pins the formatter contracts so the empty / populated /
/// missing-vital edge cases stay legible across viewmodel-state churn.
///
/// We test the pure `V6BodyTilePayload` factory methods rather than the
/// SwiftUI view tree itself — the rendering layer is dumb (already covered by
/// type-check + Preview) but the formatter logic is where real bugs hide.
@MainActor
final class V6BodyTileTests: XCTestCase {

    private var savedWeightUnit: WeightUnit = .lbs

    override func setUp() {
        super.setUp()
        // Snapshot and pin weight unit so format strings are deterministic.
        // `Preferences.weightUnit` is a static UserDefaults-backed property,
        // so we MUST restore it in tearDown — otherwise tests downstream
        // (e.g. WeightViewModel integration tests that call
        // `addWeight(value: 70.0)`) interpret the value in the wrong unit
        // and silently fail.
        savedWeightUnit = Preferences.weightUnit
        Preferences.weightUnit = .lbs
    }

    override func tearDown() {
        Preferences.weightUnit = savedWeightUnit
        super.tearDown()
    }

    // MARK: - Weight tile

    func testWeightPayloadWithNoDataShowsDoubleDash() {
        let p = V6BodyTile.weightPayload(weightKg: nil, weeklyRateKg: nil)
        XCTAssertEqual(p.label, "Weight")
        XCTAssertEqual(p.value, "--")
        XCTAssertEqual(p.unit, "lbs")
        XCTAssertNil(p.delta)
        XCTAssertEqual(p.deltaLabel, "no data")
    }

    func testWeightPayloadConvertsKgToLbsAndFormatsWeeklyRate() {
        Preferences.weightUnit = .lbs
        let p = V6BodyTile.weightPayload(weightKg: 75.0, weeklyRateKg: 0.227)
        // 75 kg = 165.34... lbs. We format with %.1f so "165.3" or "165.4"
        // depending on Foundation's rounding; both are acceptable. Pin
        // the prefix so a regression to a wrong unit is caught.
        XCTAssertTrue(p.value.hasPrefix("165."), "Expected lbs conversion ~165.x, got \(p.value)")
        XCTAssertEqual(p.unit, "lbs")
        // 0.227 kg = ~0.50 lbs. Signed format must include "+" for positive.
        XCTAssertEqual(p.delta, "+0.50 lbs/wk")
        XCTAssertEqual(p.deltaLabel, "this wk")
    }

    func testWeightPayloadFormatsNegativeRateWithMinus() {
        Preferences.weightUnit = .kg
        let p = V6BodyTile.weightPayload(weightKg: 70.0, weeklyRateKg: -0.30)
        XCTAssertEqual(p.unit, "kg")
        XCTAssertEqual(p.delta, "-0.30 kg/wk")
        XCTAssertEqual(p.deltaLabel, "this wk")
    }

    func testWeightPayloadWithWeightButNoTrendUsesLogPrompt() {
        let p = V6BodyTile.weightPayload(weightKg: 75.0, weeklyRateKg: nil)
        XCTAssertNotEqual(p.value, "--", "Has weight, must render a numeric value")
        XCTAssertNil(p.delta)
        XCTAssertEqual(p.deltaLabel, "log to track",
                       "Without a trend we nudge the user, not parrot 'no data' under a known weight")
    }

    /// Defensive: a corrupt or seeded-bogus entry must NOT render
    /// "-165.3 lbs" on the dashboard. Same guard class as Sleep's
    /// `hours <= 0 || !isFinite` clamp.
    func testWeightPayloadGuardsNegativeKg() {
        let p = V6BodyTile.weightPayload(weightKg: -75.0, weeklyRateKg: nil)
        XCTAssertEqual(p.value, "--")
        XCTAssertEqual(p.deltaLabel, "no data")
    }

    func testWeightPayloadGuardsNaNKg() {
        let p = V6BodyTile.weightPayload(weightKg: .nan, weeklyRateKg: nil)
        XCTAssertEqual(p.value, "--")
        XCTAssertEqual(p.deltaLabel, "no data")
    }

    func testWeightPayloadGuardsNonFiniteRate() {
        // Weight is fine, weekly rate is NaN — render the weight but drop the
        // bogus delta rather than emit "+nan lbs/wk".
        let p = V6BodyTile.weightPayload(weightKg: 75.0, weeklyRateKg: .nan)
        XCTAssertTrue(p.value.hasPrefix("165."))
        XCTAssertNil(p.delta)
        XCTAssertEqual(p.deltaLabel, "log to track")
    }

    /// Stale-trend signal: legacy Weight+Trend card showed "Tap to update" in
    /// yellow when the trend was older than the staleness threshold. V6 tile
    /// surfaces the same affordance by appending "· stale" to the deltaLabel.
    func testWeightPayloadAppendsStaleHintWhenIsStale() {
        let p = V6BodyTile.weightPayload(weightKg: 75.0, weeklyRateKg: 0.227, isStale: true)
        XCTAssertEqual(p.delta, "+0.50 lbs/wk")
        XCTAssertTrue(p.deltaLabel.contains("stale"),
                      "Stale trend must be visible to the user, got '\(p.deltaLabel)'")
    }

    func testWeightPayloadDoesNotAppendStaleHintWhenNoDelta() {
        // No delta → nothing to be "stale" about; don't append a confusing
        // "log to track · stale" label.
        let p = V6BodyTile.weightPayload(weightKg: 75.0, weeklyRateKg: nil, isStale: true)
        XCTAssertNil(p.delta)
        XCTAssertEqual(p.deltaLabel, "log to track")
    }

    func testWeightPayloadInKgRespectsPreference() {
        Preferences.weightUnit = .kg
        let p = V6BodyTile.weightPayload(weightKg: 75.0, weeklyRateKg: 0.5)
        XCTAssertEqual(p.value, "75.0")
        XCTAssertEqual(p.unit, "kg")
        XCTAssertEqual(p.delta, "+0.50 kg/wk")
    }

    // MARK: - Sleep tile

    func testSleepPayloadZeroHoursShowsDoubleDash() {
        let p = V6BodyTile.sleepPayload(hours: 0)
        XCTAssertEqual(p.label, "Sleep")
        XCTAssertEqual(p.value, "--")
        XCTAssertEqual(p.unit, "h")
        XCTAssertNil(p.delta)
        XCTAssertEqual(p.deltaLabel, "no data")
    }

    func testSleepPayloadFormatsHoursToOneDecimal() {
        let p = V6BodyTile.sleepPayload(hours: 7.4)
        XCTAssertEqual(p.value, "7.4")
        XCTAssertEqual(p.unit, "h")
        XCTAssertEqual(p.delta, "last night")
        XCTAssertEqual(p.deltaLabel, "")
    }

    /// NaN / infinity must not render as "nan" / "inf" in the value field.
    /// Same safety class as V6Rings' `safeValue` clamp.
    func testSleepPayloadNonFiniteHoursTreatedAsNoData() {
        let nanPayload = V6BodyTile.sleepPayload(hours: .nan)
        XCTAssertEqual(nanPayload.value, "--")
        XCTAssertEqual(nanPayload.deltaLabel, "no data")

        let infPayload = V6BodyTile.sleepPayload(hours: .infinity)
        XCTAssertEqual(infPayload.value, "--")
        XCTAssertEqual(infPayload.deltaLabel, "no data")
    }

    // MARK: - Readiness tile

    func testReadinessPayloadZeroScoreShowsDoubleDash() {
        let p = V6BodyTile.readinessPayload(recoveryScore: 0, hrvMs: 0)
        XCTAssertEqual(p.label, "Readiness")
        XCTAssertEqual(p.value, "--")
        XCTAssertNil(p.delta)
        XCTAssertEqual(p.deltaLabel, "no data")
    }

    func testReadinessPayloadWithScoreAndHRVShowsHRVDelta() {
        let p = V6BodyTile.readinessPayload(recoveryScore: 82, hrvMs: 65)
        XCTAssertEqual(p.value, "82")
        XCTAssertEqual(p.delta, "65ms HRV")
        XCTAssertEqual(p.unit, "")
        XCTAssertEqual(p.deltaLabel, "")
    }

    func testReadinessPayloadWithScoreButNoHRVFallsBackToScoreLabel() {
        let p = V6BodyTile.readinessPayload(recoveryScore: 50, hrvMs: 0)
        XCTAssertEqual(p.value, "50")
        XCTAssertNil(p.delta)
        XCTAssertEqual(p.deltaLabel, "score",
                       "Without HRV we still want a label under the value, not a blank line")
    }

    // MARK: - View construction

    /// Sanity check: a freshly constructed tile with all three payload shapes
    /// (populated / empty / partial) must not crash during init. This is
    /// effectively a Tier-1 smoke test — it pairs with the formatter asserts
    /// above to give end-to-end coverage without booting the simulator.
    func testV6BodyTileConstructsForAllPayloadShapes() {
        let populated = V6BodyTile(
            label: "Weight", value: "165.4", unit: "lbs",
            delta: "+0.50 lbs/wk", deltaLabel: "this wk",
            tone: Theme.V6.ringMove,
            onTap: {}
        )
        let empty = V6BodyTile(
            label: "Sleep", value: "--", unit: "h",
            delta: nil, deltaLabel: "no data",
            tone: Theme.V6.ringStand,
            onTap: {}
        )
        let partial = V6BodyTile(
            label: "Readiness", value: "50", unit: "",
            delta: nil, deltaLabel: "score",
            tone: Theme.V6.ringEx,
            onTap: {}
        )
        XCTAssertNotNil(populated)
        XCTAssertNotNil(empty)
        XCTAssertNotNil(partial)
    }

    // 2026-05-19: dropped `testWeightTileOnAddAndOnTapAreSeparateClosures`.
    // The "+" overlay on the Weight tile (and its `onAdd` callback) was
    // removed in the V6 polish pass — the whole tile now routes to the
    // Weight tab via `onTap`, so there is no second closure to pin.
}
