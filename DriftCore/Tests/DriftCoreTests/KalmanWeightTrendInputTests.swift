import Foundation
@testable import DriftCore
import Testing

struct KalmanWeightTrendInputTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func fewerThanTwoObservationsReturnsNil() {
        #expect(KalmanWeightTrend.run(observations: []) == nil)
        #expect(KalmanWeightTrend.run(observations: [(start, 70)]) == nil)
    }

    @Test func sameDayRepeatUpdatesWithoutCreatingRate() throws {
        let output = try #require(KalmanWeightTrend.run(observations: [
            (start, 70),
            (start, 71),
        ]))

        #expect(output.filteredSeries.count == 2)
        #expect(output.filteredSeries.allSatisfy { $0.date == start })
        #expect(output.weight > 70 && output.weight < 71)
        #expect(output.waterKg > 0)
        #expect(output.weeklyRateKg == 0)
    }

    @Test func constantSeriesProducesFiniteStableOutput() throws {
        let observations = (0..<5).map { day in
            (start.addingTimeInterval(Double(day) * 86_400), 72.5)
        }
        let output = try #require(KalmanWeightTrend.run(observations: observations))

        #expect(output.filteredSeries.count == observations.count)
        #expect(output.filteredSeries.map(\.date) == observations.map(\.0))
        #expect(output.filteredSeries.allSatisfy { $0.weight.isFinite })
        #expect(output.weight == 72.5)
        #expect(output.waterKg == 0)
        #expect(output.weeklyRateKg == 0)
        #expect(output.weeklyRateStd.isFinite && output.weeklyRateStd > 0)
        #expect(output.rateZ == 0)
    }
}
