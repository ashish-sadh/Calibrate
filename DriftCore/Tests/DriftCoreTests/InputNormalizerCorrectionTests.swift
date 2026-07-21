@testable import DriftCore
import Testing

@Test func inputNormalizerUsesLatestMidSentenceCorrection() {
    let result = InputNormalizer.removeMidSentenceCorrections(
        "log rice no I mean pasta no wait I mean eggs"
    )

    #expect(result == "eggs")
}

@Test func inputNormalizerMatchesCorrectionMarkersCaseInsensitively() {
    let result = InputNormalizer.removeMidSentenceCorrections(
        "I ate rice ACTUALLY I MEANT Paneer"
    )

    #expect(result == "Paneer")
}

@Test func inputNormalizerKeepsTextWhenCorrectionHasNoReplacement() {
    let input = "log rice no wait "

    #expect(InputNormalizer.removeMidSentenceCorrections(input) == input)
}

@Test func inputNormalizerProcessesReplacementThroughRemainingPipeline() {
    let result = InputNormalizer.normalize(
        "log rice no wait i mean umm whats my protein"
    )

    #expect(result == "what's my protein")
}
