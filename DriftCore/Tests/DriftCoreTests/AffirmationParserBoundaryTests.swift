@testable import DriftCore
import Testing

@Suite struct AffirmationParserBoundaryTests {
    @Test func punctuationCaseAndWhitespaceAreNormalized() {
        #expect(AffirmationParser.verdict("\n  YES!!!\t") == .yes)
        #expect(AffirmationParser.verdict("\tNO???\n") == .no)
    }

    @Test func negativePhraseWinsEvenWhenAffirmativeWordIsPresent() {
        #expect(AffirmationParser.verdict("please, no thank you") == .no)
        #expect(AffirmationParser.verdict("okay, wait no") == .no)
    }

    @Test func terseTokenLimitIncludesFourButRejectsFive() {
        #expect(AffirmationParser.verdict("well this seems definitely") == .yes)
        #expect(AffirmationParser.verdict("well this really seems definitely") == .unclear)
    }

    @Test func explicitPhraseCanResolveLongerReply() {
        #expect(AffirmationParser.verdict("after thinking about it please go ahead") == .yes)
        #expect(AffirmationParser.verdict("after thinking about it please hold on") == .no)
    }

    @Test func apostropheNegationReflectsCurrentNormalizationBehavior() {
        #expect(AffirmationParser.verdict("don't") == .unclear)
        #expect(AffirmationParser.verdict("don't do that") == .yes)
    }
}
