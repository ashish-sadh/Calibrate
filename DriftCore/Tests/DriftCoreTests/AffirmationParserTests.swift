import Foundation
@testable import DriftCore
import Testing

// Shared yes/no resolver for talk-mode action confirms. #coach-talk-mode

@Test func affirmationYes() {
    for s in ["yes", "Yes!", "yeah", "yep", "sure", "ok", "okay", "confirm",
              "go ahead", "do it", "add it", "log it", "yes please", "correct"] {
        #expect(AffirmationParser.verdict(s) == .yes, "expected yes for \(s)")
    }
}

@Test func affirmationNo() {
    for s in ["no", "No.", "nope", "nah", "cancel", "stop", "never mind",
              "nevermind", "scratch that", "no thanks", "forget it", "wrong"] {
        #expect(AffirmationParser.verdict(s) == .no, "expected no for \(s)")
    }
}

@Test func affirmationUnclear() {
    for s in ["", "   ", "maybe", "what", "tell me more", "how many calories",
              "knot", "yesterday"] {
        #expect(AffirmationParser.verdict(s) == .unclear, "expected unclear for \(s)")
    }
}

@Test func negativeBeatsAmbiguous() {
    // "no thanks" contains "thanks" — must not read as yes.
    #expect(AffirmationParser.verdict("no thanks") == .no)
    // a yes word + a no word → safety-biased to no.
    #expect(AffirmationParser.verdict("yes no") == .no)
}
