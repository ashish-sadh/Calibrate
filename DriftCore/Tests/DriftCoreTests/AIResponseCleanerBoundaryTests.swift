@testable import DriftCore
import Testing

@Test func responseCleanerConvertsOnlyLineStartMarkdownBullets() {
    let response = "Daily deficit -300 kcal.\n- Walk 20 minutes."

    #expect(AIResponseCleaner.clean(response) == "Daily deficit -300 kcal.\n• Walk 20 minutes.")
}

@Test func responseCleanerConvertsMultiDigitNumberedListMarkers() {
    let response = "10. Walk after lunch.\n2. Stretch before bed."

    #expect(AIResponseCleaner.clean(response) == "10) Walk after lunch.\n2) Stretch before bed.")
}

@Test func responseCleanerDeduplicatesSentencesCaseInsensitively() {
    let response = "Stay hydrated. stay hydrated. Eat well."

    #expect(AIResponseCleaner.clean(response) == "Stay hydrated. Eat well.")
}

@Test func responseCleanerAllowsExactlyTwoUnknownNumbers() {
    let response = "Targets could be 250, 300, or your current goal."

    #expect(AIResponseCleaner.hasHallucinatedNumbers(response, context: "Current goal: 2000.") == false)
}

@Test func responseCleanerFlagsThreeUnknownNumbers() {
    let response = "Targets could be 250, 300, or 350."

    #expect(AIResponseCleaner.hasHallucinatedNumbers(response, context: "Current goal: 2000.") == true)
}

@Test func responseCleanerIgnoresNumbersLongerThanFiveDigits() {
    let response = "Internal reference 123456."

    #expect(AIResponseCleaner.hasHallucinatedNumbers(response, context: "Current goal: 2000.") == false)
}
