import Testing
@testable import DriftCore

@Suite struct GlucoseReadingZoneTests {
    private func reading(_ glucoseMgdl: Double) -> GlucoseReading {
        GlucoseReading(timestamp: "2026-07-21T12:00:00Z", glucoseMgdl: glucoseMgdl)
    }

    @Test func valuesBelow70AreLow() {
        #expect(reading(69.999).zone == .low)
    }

    @Test func valuesFrom70UpTo100AreNormal() {
        #expect(reading(70).zone == .normal)
        #expect(reading(99.999).zone == .normal)
    }

    @Test func valuesFrom100UpTo140AreElevated() {
        #expect(reading(100).zone == .elevated)
        #expect(reading(139.999).zone == .elevated)
    }

    @Test func valuesAtOrAbove140AreHigh() {
        #expect(reading(140).zone == .high)
        #expect(reading(250).zone == .high)
    }
}
