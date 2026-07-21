import Testing
@testable import DriftCore

@Suite struct PromptUtilsTests {
    @Test func estimateTokensUsesFourUtf8BytesPerToken() {
        #expect(PromptUtils.estimateTokens("") == 0)
        #expect(PromptUtils.estimateTokens("1234567") == 1)
        #expect(PromptUtils.estimateTokens("éé") == 1)
        #expect(PromptUtils.estimateTokens("🙂") == 1)
    }

    @Test func contextAtBudgetIsReturnedUnchanged() {
        let context = "12345678"

        #expect(PromptUtils.truncateToFit(context, maxTokens: 2) == context)
    }

    @Test func truncationPreservesCompleteLines() {
        let context = "first\nsecond\nthirdmore"

        #expect(PromptUtils.truncateToFit(context, maxTokens: 4) == "first\nsecond\n")
    }

    @Test func singleLineContextFallsBackToCharacterLimit() {
        #expect(PromptUtils.truncateToFit("abcdefghijkl", maxTokens: 2) == "abcdefgh")
        #expect(PromptUtils.truncateToFit("content", maxTokens: 0).isEmpty)
    }
}
