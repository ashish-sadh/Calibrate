import Testing
import Foundation
@testable import DriftCore

/// Tier 0 — forgiving unit input ("take whatever", operator 2026-07-14):
/// tape measurements accept cm/in/mm suffixes, workout weights accept kg/lb.
struct FlexibleUnitInputTests {

    private func approx(_ a: Double?, _ b: Double, tol: Double = 0.01) -> Bool {
        guard let a else { return false }
        return abs(a - b) <= tol
    }

    // MARK: - Length (measurements)

    @Test func bareNumberUsesDisplayUnit() {
        #expect(approx(FlexibleUnitInput.lengthCm(from: "86", assumeInches: false), 86))
        #expect(approx(FlexibleUnitInput.lengthCm(from: "34", assumeInches: true), 34 * 2.54))
        #expect(approx(FlexibleUnitInput.lengthCm(from: "34,5", assumeInches: true), 34.5 * 2.54))  // comma decimal
    }

    @Test func explicitSuffixOverridesDisplayUnit() {
        // cm typed on an inches form — the AG1-adjacent "struggle with units" ask.
        #expect(approx(FlexibleUnitInput.lengthCm(from: "86cm", assumeInches: true), 86))
        #expect(approx(FlexibleUnitInput.lengthCm(from: "86 cm", assumeInches: true), 86))
        #expect(approx(FlexibleUnitInput.lengthCm(from: "34in", assumeInches: false), 34 * 2.54))
        #expect(approx(FlexibleUnitInput.lengthCm(from: "34\"", assumeInches: false), 34 * 2.54))
        #expect(approx(FlexibleUnitInput.lengthCm(from: "34 inches", assumeInches: false), 34 * 2.54))
        #expect(approx(FlexibleUnitInput.lengthCm(from: "860mm", assumeInches: true), 86))
    }

    @Test func junkReturnsNil() {
        #expect(FlexibleUnitInput.lengthCm(from: "", assumeInches: false) == nil)
        #expect(FlexibleUnitInput.lengthCm(from: "abc", assumeInches: false) == nil)
        #expect(FlexibleUnitInput.lengthCm(from: "34 bananas", assumeInches: false) == nil)  // never guess
        #expect(FlexibleUnitInput.lengthCm(from: "0", assumeInches: false) == nil)
    }

    // MARK: - Weight (workouts; bare = lbs, the field's long-standing meaning)

    @Test func bareWeightStaysLbs() {
        #expect(approx(FlexibleUnitInput.weightLbs(from: "135"), 135))
        #expect(approx(FlexibleUnitInput.weightLbs(from: "62,5"), 62.5))   // #1022 comma decimal
        #expect(approx(FlexibleUnitInput.weightLbs(from: "135 lbs"), 135))
        #expect(approx(FlexibleUnitInput.weightLbs(from: "135lb"), 135))
    }

    @Test func kgSuffixConverts() {
        #expect(approx(FlexibleUnitInput.weightLbs(from: "60kg"), 60 * 2.20462))
        #expect(approx(FlexibleUnitInput.weightLbs(from: "60 kg"), 60 * 2.20462))
        #expect(approx(FlexibleUnitInput.weightLbs(from: "22.5kgs"), 22.5 * 2.20462))
    }

    @Test func weightJunkReturnsNil() {
        #expect(FlexibleUnitInput.weightLbs(from: "") == nil)
        #expect(FlexibleUnitInput.weightLbs(from: "heavy") == nil)
        #expect(FlexibleUnitInput.weightLbs(from: "60 stones") == nil)
    }

    // MARK: - Resolver integration (suffix respected end-to-end)

    @Test func resolverHonorsSuffixOnInchesForm() {
        let fields: [MeasurementSite: BodyMeasurementAnalysis.FieldInput] = [
            .waist: .init(enteredText: "86cm", loadedText: nil, loadedCm: nil, ghostCm: nil),
            .chest: .init(enteredText: "40", loadedText: nil, loadedCm: nil, ghostCm: nil),
        ]
        let out = BodyMeasurementAnalysis.resolveMeasurements(fields, inInches: true)
        #expect(approx(out[MeasurementSite.waist.rawValue], 86))            // suffix wins
        #expect(approx(out[MeasurementSite.chest.rawValue], 40 * 2.54))    // bare uses form unit
    }
}
