import Foundation
@testable import DriftCore
import Testing

@Test func extractorCapturesGoals() {
    let items = CoachMemoryExtractor.extract(from: "I want to hit 90g protein daily")
    #expect(items.contains { $0.kind == .goal })
}

@Test func extractorCapturesPreferences() {
    let items = CoachMemoryExtractor.extract(from: "I'm vegetarian and I avoid dairy")
    #expect(items.contains { $0.kind == .preference })
}

@Test func extractorCapturesExplicitRemember() {
    let items = CoachMemoryExtractor.extract(from: "Remember that my knee hurts on squats")
    #expect(items.count == 1)
    #expect(items.first?.kind == .fact)
}

@Test func extractorIgnoresPlainChatter() {
    #expect(CoachMemoryExtractor.extract(from: "log 2 eggs").isEmpty)
    #expect(CoachMemoryExtractor.extract(from: "how many calories left").isEmpty)
    #expect(CoachMemoryExtractor.extract(from: "ok").isEmpty)   // too short
}
