import Foundation
@testable import DriftCore
import Testing

@Suite struct OvulationEntryTests {
    @Test(arguments: [2, 4])
    func surgeResultsArePositive(result: Int) {
        let entry = OvulationEntry(date: Date(timeIntervalSince1970: 0), result: result)

        #expect(entry.isPositive)
    }

    @Test(arguments: [-1, 0, 1, 3, 5, Int.max])
    func nonSurgeAndUnknownResultsAreNotPositive(result: Int) {
        let entry = OvulationEntry(date: Date(timeIntervalSince1970: 0), result: result)

        #expect(!entry.isPositive)
    }
}
