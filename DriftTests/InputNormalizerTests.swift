import Foundation
import Testing
@testable import Drift

// MARK: - InputNormalizer Tests

// MARK: Filler Word Removal

@Test func normalizerRemovesUmm() {
    let result = InputNormalizer.normalize("umm I had 2 eggs")
    #expect(result == "I had 2 eggs")
}

@Test func normalizerRemovesUhAndLike() {
    let result = InputNormalizer.normalize("uh like I ate some rice")
    #expect(result == "I ate some rice")
}

@Test func normalizerRemovesMultiWordFillers() {
    let result = InputNormalizer.normalize("you know I had breakfast")
    #expect(result == "I had breakfast")
}

@Test func normalizerRemovesIMean() {
    let result = InputNormalizer.normalize("i mean I want to log lunch")
    #expect(result == "I want to log lunch")
}

@Test func normalizerKeepsMeaningfulLike() {
    // "like" as filler is removed, but the content meaning is preserved
    let result = InputNormalizer.normalize("I had like 3 bananas")
    #expect(result == "I had 3 bananas")
}

// MARK: Partial Restarts

@Test func normalizerRemovesPartialRestart() {
    let result = InputNormalizer.removePartialRestarts("I had I had 2 eggs")
    #expect(result == "I had 2 eggs")
}

@Test func normalizerRemovesSingleWordRestart() {
    let result = InputNormalizer.removePartialRestarts("log log rice and dal")
    #expect(result == "log rice and dal")
}

@Test func normalizerRemovesTwoWordRestart() {
    let result = InputNormalizer.removePartialRestarts("I ate I ate chicken for dinner")
    #expect(result == "I ate chicken for dinner")
}

@Test func normalizerNoRestartWhenDifferent() {
    let result = InputNormalizer.removePartialRestarts("I had rice and dal")
    #expect(result == "I had rice and dal")
}

// MARK: Repeated Words

@Test func normalizerCollapsesRepeatedWords() {
    let result = InputNormalizer.collapseRepeatedWords("the the rice")
    #expect(result == "the rice")
}

@Test func normalizerCollapsesMultipleRepeats() {
    let result = InputNormalizer.collapseRepeatedWords("I I I ate ate rice")
    #expect(result == "I ate rice")
}

@Test func normalizerKeepsDistinctWords() {
    let result = InputNormalizer.collapseRepeatedWords("rice and dal")
    #expect(result == "rice and dal")
}

// MARK: Contractions

@Test func normalizerFixesDont() {
    let result = InputNormalizer.fixCommonContractions("I dont want rice")
    #expect(result == "I don't want rice")
}

@Test func normalizerFixesIm() {
    let result = InputNormalizer.fixCommonContractions("im at 165 pounds")
    #expect(result == "I'm at 165 pounds")
}

@Test func normalizerFixesWhats() {
    let result = InputNormalizer.fixCommonContractions("whats my protein")
    #expect(result == "what's my protein")
}

@Test func normalizerPreservesExistingApostrophe() {
    let result = InputNormalizer.fixCommonContractions("I don't want rice")
    #expect(result == "I don't want rice")
}

// MARK: Whitespace

@Test func normalizerCollapsesWhitespace() {
    let result = InputNormalizer.normalizeWhitespace("I  had    rice")
    #expect(result == "I had rice")
}

@Test func normalizerHandlesTabs() {
    let result = InputNormalizer.normalizeWhitespace("I\thad\trice")
    #expect(result == "I had rice")
}

@Test func normalizerHandlesNewlines() {
    let result = InputNormalizer.normalizeWhitespace("I had\nrice")
    #expect(result == "I had rice")
}

// MARK: Leading Conjunctions

@Test func normalizerStripsLeadingSo() {
    let result = InputNormalizer.trimLeadingConjunctions("so I had rice")
    #expect(result == "I had rice")
}

@Test func normalizerStripsOkSo() {
    let result = InputNormalizer.trimLeadingConjunctions("ok so log my lunch")
    #expect(result == "log my lunch")
}

@Test func normalizerStripsWell() {
    let result = InputNormalizer.trimLeadingConjunctions("well I want to log eggs")
    #expect(result == "I want to log eggs")
}

@Test func normalizerKeepsSoInMiddle() {
    let result = InputNormalizer.trimLeadingConjunctions("I had rice so log it")
    #expect(result == "I had rice so log it")
}

// MARK: Full Pipeline (End-to-End)

@Test func normalizerFullVoiceInput() {
    let result = InputNormalizer.normalize("umm so I had like 2 eggs and and some toast for breakfast")
    #expect(result == "I had 2 eggs and some toast for breakfast")
}

@Test func normalizerFullCleanInput() {
    // Clean input should pass through unchanged
    let result = InputNormalizer.normalize("log 3 eggs")
    #expect(result == "log 3 eggs")
}

@Test func normalizerFullRestart() {
    let result = InputNormalizer.normalize("I had I had umm 2 bananas")
    #expect(result == "I had 2 bananas")
}

@Test func normalizerEmptyInput() {
    let result = InputNormalizer.normalize("")
    #expect(result == "")
}

@Test func normalizerOnlyFillers() {
    // If everything is filler, return original trimmed
    let result = InputNormalizer.normalize("umm uh like")
    #expect(!result.isEmpty)
}

@Test func normalizerPreservesNumbers() {
    let result = InputNormalizer.normalize("umm like 200 grams of rice")
    #expect(result == "200 grams of rice")
}

@Test func normalizerPreservesSpecialFood() {
    let result = InputNormalizer.normalize("uh I had paneer tikka masala")
    #expect(result == "I had paneer tikka masala")
}

@Test func normalizerVoiceStyleNoFiller() {
    // Voice input without fillers but with restarts
    let result = InputNormalizer.normalize("log log rice and dal")
    #expect(result == "log rice and dal")
}

@Test func normalizerContractionAndFiller() {
    let result = InputNormalizer.normalize("um whats my calories left")
    #expect(result == "what's my calories left")
}

@Test func normalizerComplexVoice() {
    let result = InputNormalizer.normalize("ok so umm I basically had like chicken and rice for lunch")
    #expect(result == "I had chicken and rice for lunch")
}

// MARK: Voice-Style Input Test Cases (#85)
// Real transcription patterns: no caps, no punctuation, fillers, restarts, run-ons.

@Test func normalizerVoice_allLowerNoPunctuation() {
    let result = InputNormalizer.normalize("log breakfast two eggs and some toast")
    #expect(!result.isEmpty)
    #expect(result.contains("eggs") && result.contains("toast"))
}

@Test func normalizerVoice_runOnMultiFood() {
    let result = InputNormalizer.normalize("i had rice and chicken and also some yogurt")
    // Fillers removed, meaningful content preserved
    #expect(result.contains("rice"))
    #expect(result.contains("chicken"))
    #expect(result.contains("yogurt"))
}

@Test func normalizerVoice_fillerPlusRestart() {
    let result = InputNormalizer.normalize("umm i had i had like some chicken for dinner")
    #expect(result.contains("chicken"))
    #expect(!result.contains("umm"))
    // Restart "i had i had" collapses to "i had"
    let hadCount = result.components(separatedBy: "had").count - 1
    #expect(hadCount <= 1, "Restart should be collapsed to single occurrence")
}

@Test func normalizerVoice_longCompoundWithFillers() {
    let result = InputNormalizer.normalize("ok so basically i had some rice and dal and then i also had some chai")
    #expect(result.contains("rice"))
    #expect(result.contains("dal"))
    #expect(result.contains("chai"))
    #expect(!result.contains("basically"))
}

@Test func normalizerVoice_repeatedConjunction() {
    let result = InputNormalizer.normalize("i had rice and and dal")
    #expect(result.contains("rice"))
    #expect(result.contains("dal"))
    // Repeated "and and" should collapse
    #expect(!result.contains("and and"))
}

@Test func normalizerVoice_multipleFillerTypes() {
    let result = InputNormalizer.normalize("you know um i basically had like chicken you know")
    #expect(result.contains("chicken"))
    #expect(!result.contains("you know"))
    #expect(!result.contains("basically"))
}

@Test func normalizerVoice_trailingFillers() {
    let result = InputNormalizer.normalize("i had eggs and stuff")
    // "and stuff" preserved — not a filler word
    #expect(result.contains("eggs"))
}

@Test func normalizerVoice_extraWhitespace() {
    let result = InputNormalizer.normalize("i   had    rice   and   dal")
    #expect(result == "i had rice and dal")
}

@Test func normalizerVoice_mixedCaseWithFillers() {
    let result = InputNormalizer.normalize("UM I Had LIKE Some RICE")
    // Fillers removed case-insensitively; content preserved
    #expect(result.lowercased().contains("rice"))
    #expect(!result.lowercased().contains("um"))
}

@Test func normalizerVoice_weightLogStyle() {
    let result = InputNormalizer.normalize("um so my weight is like 72 kilos")
    #expect(result.contains("72"))
    #expect(result.contains("kilos") || result.contains("weight"))
    #expect(!result.contains("um"))
}

@Test func normalizerVoice_contractionAndFiller_combined() {
    let result = InputNormalizer.normalize("umm whats my protein today")
    #expect(result.contains("what's") || result.contains("protein"))
    #expect(!result.contains("umm"))
}

@Test func normalizerVoice_wellPrefix_stripped() {
    // "well" is a leading conjunction — gets stripped; "so" may remain (one-pass)
    let result = InputNormalizer.normalize("well so I want to log lunch")
    #expect(result.contains("log") && result.contains("lunch"))
    #expect(!result.hasPrefix("well"))
}

@Test func normalizerVoice_chainedRestartWithFiller() {
    let result = InputNormalizer.normalize("log log log umm rice and dal")
    #expect(result.contains("rice"))
    #expect(result.contains("dal"))
    // Multiple restarts should collapse
    let logCount = result.components(separatedBy: " ").filter { $0.lowercased() == "log" }.count
    #expect(logCount <= 1)
}

// MARK: - Mid-Sentence Corrections (#117)
// Voice users correct themselves mid-sentence. Strip everything before the correction marker.

@Test func normalizerCorrection_noWaitIMean() {
    let result = InputNormalizer.removeMidSentenceCorrections("chicken no wait I mean rice")
    #expect(result == "rice")
}

@Test func normalizerCorrection_actuallyNo() {
    let result = InputNormalizer.removeMidSentenceCorrections("log eggs actually no pancakes")
    #expect(result == "pancakes")
}

@Test func normalizerCorrection_iMeant() {
    let result = InputNormalizer.removeMidSentenceCorrections("I had 2 eggs i meant 3 eggs")
    #expect(result == "3 eggs")
}

@Test func normalizerCorrection_waitNo() {
    let result = InputNormalizer.removeMidSentenceCorrections("had rice wait no I had chicken")
    #expect(result.lowercased().contains("chicken"))
}

@Test func normalizerCorrection_noIMean() {
    let result = InputNormalizer.removeMidSentenceCorrections("log biryani no I mean butter chicken")
    #expect(result == "butter chicken")
}

@Test func normalizerCorrection_noMatchPreservesOriginal() {
    let result = InputNormalizer.removeMidSentenceCorrections("log 2 eggs and toast")
    #expect(result == "log 2 eggs and toast")
}

@Test func normalizerCorrection_fullPipeline() {
    // Through full normalize: filler + correction + conjunction
    let result = InputNormalizer.normalize("umm so log chicken no wait I mean rice and dal")
    #expect(result.contains("rice"))
    #expect(result.contains("dal"))
    #expect(!result.contains("chicken"))
}

@Test func normalizerCorrection_actuallyIMeant() {
    let result = InputNormalizer.removeMidSentenceCorrections("two eggs actually i meant three eggs")
    #expect(result == "three eggs")
}

@Test func normalizerCorrection_sorryIMean() {
    let result = InputNormalizer.removeMidSentenceCorrections("log dal sorry i mean rajma")
    #expect(result == "rajma")
}

@Test func normalizerCorrection_emptyAfterMarkerPreservesOriginal() {
    // If correction marker is at the end with nothing after, keep original
    let result = InputNormalizer.removeMidSentenceCorrections("rice no wait I mean ")
    #expect(!result.isEmpty)
}
