import Foundation
@testable import DriftCore
import Testing

@Suite struct CycleEntryTests {
    @Test func flowDisplayMapsHealthKitCodes() {
        let date = Date(timeIntervalSince1970: 0)
        let expectedDisplays = [
            1: "Unspecified",
            2: "Light",
            3: "Medium",
            4: "Heavy",
            5: "None",
        ]

        for (flow, expectedDisplay) in expectedDisplays {
            #expect(CycleEntry(date: date, flow: flow).flowDisplay == expectedDisplay)
        }
    }

    @Test(arguments: [-1, 0, 6, Int.max])
    func flowDisplayFallsBackForUnknownCodes(flow: Int) {
        let entry = CycleEntry(date: Date(timeIntervalSince1970: 0), flow: flow)

        #expect(entry.flowDisplay == "Unknown")
    }
}
