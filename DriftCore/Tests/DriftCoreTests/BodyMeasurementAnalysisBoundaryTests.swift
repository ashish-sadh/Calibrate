import Testing
@testable import DriftCore

@Suite struct BodyMeasurementAnalysisBoundaryTests {
    private func measurement(_ values: [MeasurementSite: Double]) -> BodyMeasurement {
        BodyMeasurement(
            date: "2026-07-21",
            measurementsCm: Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
        )
    }

    @Test func deltasFollowDisplayOrderRegardlessOfInputOrder() {
        let previous = measurement([.waist: 80, .neck: 40, .rightCalf: 36])
        let current = measurement([.rightCalf: 36.5, .neck: 39.5, .waist: 80])

        let deltas = BodyMeasurementAnalysis.deltas(from: previous, to: current)

        #expect(deltas.map(\.site) == [.neck, .waist, .rightCalf])
        #expect(deltas.map(\.changeCm) == [-0.5, 0, 0.5])
    }

    @Test func exactSymmetryNoiseBoundaryReportsTheLargerSide() throws {
        let result = BodyMeasurementAnalysis.symmetry(in: measurement([
            .leftBicep: 35,
            .rightBicep: 35.5,
            .leftCalf: 38,
        ]))

        let symmetry = try #require(result.first)
        #expect(result.count == 1, "an incomplete left/right pair is omitted")
        #expect(symmetry.differenceCm == 0.5)
        #expect(symmetry.largerSide == .rightBicep)
    }

    @Test func ratioInterpretationsChangeAtDocumentedBoundaries() throws {
        func interpretation(waist: Double, denominator: Double, id: String) throws -> String {
            let denominatorSite: MeasurementSite = id == "whr" ? .hips : .chest
            let ratios = BodyMeasurementAnalysis.ratios(in: measurement([
                .waist: waist,
                denominatorSite: denominator,
            ]))
            return try #require(ratios.first { $0.id == id }).interpretation
        }

        #expect(try interpretation(waist: 84.9, denominator: 100, id: "whr") == "lower-risk range")
        #expect(try interpretation(waist: 85, denominator: 100, id: "whr") == "moderate range")
        #expect(try interpretation(waist: 95, denominator: 100, id: "whr") == "higher cardio-metabolic risk range")

        #expect(try interpretation(waist: 74.9, denominator: 100, id: "wcr") == "strong V-taper")
        #expect(try interpretation(waist: 75, denominator: 100, id: "wcr") == "athletic taper")
        #expect(try interpretation(waist: 85, denominator: 100, id: "wcr") == "straighter torso")
    }

    @Test func changeSummaryIncludesExactHalfCentimeterMove() {
        let previous = measurement([.waist: 80])
        let current = measurement([.waist: 79.5])

        #expect(
            BodyMeasurementAnalysis.changeSummary(from: previous, to: current, inInches: false)
                == "Waist −0.5 cm since your last check-in."
        )
    }

    @Test func fieldResolutionAcceptsCommaDecimalsAndRejectsNonPositiveValues() {
        let fields: [MeasurementSite: BodyMeasurementAnalysis.FieldInput] = [
            .waist: .init(enteredText: " 31,5 ", loadedText: nil, loadedCm: nil, ghostCm: nil),
            .chest: .init(enteredText: "0", loadedText: nil, loadedCm: nil, ghostCm: nil),
            .neck: .init(enteredText: "-1", loadedText: nil, loadedCm: nil, ghostCm: nil),
            .hips: .init(enteredText: "not a number", loadedText: nil, loadedCm: nil, ghostCm: nil),
        ]

        let resolved = BodyMeasurementAnalysis.resolveMeasurements(fields, inInches: true)

        #expect(Set(resolved.keys) == [MeasurementSite.waist.rawValue])
        #expect(abs((resolved[MeasurementSite.waist.rawValue] ?? 0) - 80.01) < 0.000_001)
    }
}
