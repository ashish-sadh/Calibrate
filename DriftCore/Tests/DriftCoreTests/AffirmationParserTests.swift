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

@Test func longCorrectiveSentenceIsUnclearNotCancel() {
    // A correction that happens to start with "no" must NOT read as a bare
    // cancel — it should route to a fresh turn. #coach-talk-mode
    #expect(AffirmationParser.verdict("no, I had chicken instead") == .unclear)
    #expect(AffirmationParser.verdict("yes but make it two servings of rice") == .unclear)
    // Terse confirmations still resolve.
    #expect(AffirmationParser.verdict("yeah do it") == .yes)
    #expect(AffirmationParser.verdict("no") == .no)
}
