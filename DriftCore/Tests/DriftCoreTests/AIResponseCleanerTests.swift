import Foundation
@testable import DriftCore
import Testing

// MARK: - AIResponseCleaner.clean() Tests

@Test func clean_removesImStartToken() {
    let result = AIResponseCleaner.clean("<|im_start|>Hello there.")
    #expect(!result.contains("<|im_start|>"))
    #expect(result.contains("Hello"))
}

@Test func clean_removesImEndToken() {
    let result = AIResponseCleaner.clean("Hello<|im_end|>")
    #expect(!result.contains("<|im_end|>"))
}

@Test func clean_removesGemmaTokens() {
    let result = AIResponseCleaner.clean("<start_of_turn>Hello.<end_of_turn>")
    #expect(!result.contains("<start_of_turn>"))
    #expect(!result.contains("<end_of_turn>"))
}

@Test func clean_removesAssistantShortPrefix() {
    let result = AIResponseCleaner.clean("A: Hello there.")
    #expect(!result.hasPrefix("A: "))
    #expect(result.hasPrefix("Hello"))
}

@Test func clean_removesAssistantLongPrefix() {
    let result = AIResponseCleaner.clean("assistant: Your calories are 200.")
    #expect(!result.lowercased().hasPrefix("assistant:"))
    #expect(result.contains("calories"))
}

@Test func clean_removesMarkdownBold() {
    let result = AIResponseCleaner.clean("You have **200** calories left.")
    #expect(!result.contains("**"))
    #expect(result.contains("200"))
}

@Test func clean_removesMarkdownH2() {
    let result = AIResponseCleaner.clean("## Summary\nYou did well.")
    #expect(!result.contains("## "))
}

@Test func clean_removesPreamble_basedOnYourData() {
    let result = AIResponseCleaner.clean("Based on your data, you have 200 calories left.")
    #expect(!result.lowercased().hasPrefix("based on your data"))
    #expect(result.hasPrefix("You"))
}

@Test func clean_removesPreamble_greatQuestion() {
    let result = AIResponseCleaner.clean("Great question! Your protein is on track.")
    #expect(!result.lowercased().hasPrefix("great question"))
    #expect(result.hasPrefix("Your"))
}

@Test func clean_removesPreamble_sureExclamation() {
    let result = AIResponseCleaner.clean("Sure! Here are your stats.")
    #expect(!result.lowercased().hasPrefix("sure!"))
    #expect(result.hasPrefix("Here"))
}

@Test func clean_removesAIDisclaimerSentence() {
    let result = AIResponseCleaner.clean("You had 200 calories. As an AI I cannot provide medical advice. Track your meals.")
    #expect(!result.lowercased().contains("as an ai"))
    #expect(result.contains("200 calories"))
}

@Test func clean_deduplicatesSentences() {
    let result = AIResponseCleaner.clean("Hello. Hello. World.")
    let count = result.components(separatedBy: "Hello").count - 1
    #expect(count == 1)
}

@Test func clean_truncatesLongResponse() {
    let long = String(repeating: "You are doing well today. ", count: 25)  // >500 chars
    let result = AIResponseCleaner.clean(long)
    #expect(result.count <= 500)
    #expect(result.hasSuffix("."))
}

@Test func clean_shortResponsePassesThrough() {
    let result = AIResponseCleaner.clean("You had 200 calories.")
    #expect(result == "You had 200 calories.")
}

@Test func clean_emptyStringReturnsEmpty() {
    let result = AIResponseCleaner.clean("")
    #expect(result.isEmpty)
}

@Test func clean_removesTrailingIncompleteFragment() {
    let result = AIResponseCleaner.clean("You did well today. This is incomplete")
    #expect(result == "You did well today.")
}

@Test func clean_preservesValidPunctuation_exclamation() {
    let result = AIResponseCleaner.clean("Great job!")
    #expect(result == "Great job!")
}

@Test func clean_preservesValidPunctuation_question() {
    let result = AIResponseCleaner.clean("How can I help you?")
    #expect(result == "How can I help you?")
}

// MARK: - AIResponseCleaner.isLowQuality() Tests

@Test func isLowQuality_tooShortReturnsTrue() {
    #expect(AIResponseCleaner.isLowQuality("ok") == true)
}

@Test func isLowQuality_emptyReturnsTrue() {
    #expect(AIResponseCleaner.isLowQuality("") == true)
}

@Test func isLowQuality_genericFillerReturnsTrue() {
    #expect(AIResponseCleaner.isLowQuality("I'm here to help you today") == true)
}

@Test func isLowQuality_howCanIAssistReturnsTrue() {
    #expect(AIResponseCleaner.isLowQuality("How can I assist you") == true)
}

@Test func isLowQuality_normalResponseReturnsFalse() {
    #expect(AIResponseCleaner.isLowQuality("You had 200 calories today and 50g of protein.") == false)
}

@Test func isLowQuality_pureRepetitionReturnsTrue() {
    // word repetition ratio < 0.3
    #expect(AIResponseCleaner.isLowQuality("the the the the the the the the the the") == true)
}

@Test func isLowQuality_manyPipesReturnsTrue() {
    #expect(AIResponseCleaner.isLowQuality("eaten: | weight: | goal: | calories: |") == true)
}

@Test func isLowQuality_eatenPrefixReturnsTrue() {
    #expect(AIResponseCleaner.isLowQuality("eaten: 200 protein: 50 carbs: 30") == true)
}

@Test func isLowQuality_weightPrefixReturnsTrue() {
    #expect(AIResponseCleaner.isLowQuality("weight: 70 goal: 65") == true)
}

@Test func isLowQuality_actionTagReturnsTrue() {
    #expect(AIResponseCleaner.isLowQuality("use action tag [log_food to log your food") == true)
}

@Test func isLowQuality_iCannotReturnsTrue() {
    #expect(AIResponseCleaner.isLowQuality("I cannot answer that question.") == true)
}

@Test func isLowQuality_garbageCharsReturnsTrue() {
    #expect(AIResponseCleaner.isLowQuality("!!!@@###$$$%%%^^^&&&***") == true)
}

@Test func isLowQuality_shortQuestionNoNumbersReturnsTrue() {
    // Short response with ? and no numbers + no follow-up words → repetition of question
    #expect(AIResponseCleaner.isLowQuality("Are you hungry?") == true)
}

@Test func isLowQuality_followUpQuestionReturnsFalse() {
    // Contains "how much" which is a follow-up word → not low quality
    #expect(AIResponseCleaner.isLowQuality("How much protein would you like to log?") == false)
}

// MARK: - AIResponseCleaner.hasHallucinatedNumbers() Tests

@Test func hasHallucinatedNumbers_noNumbersInResponseReturnsFalse() {
    #expect(AIResponseCleaner.hasHallucinatedNumbers("You did great today!", context: "weight: 70") == false)
}

@Test func hasHallucinatedNumbers_noContextNumbersReturnsFalse() {
    #expect(AIResponseCleaner.hasHallucinatedNumbers("You had 250 calories.", context: "no numbers here") == false)
}

@Test func hasHallucinatedNumbers_responseNumbersMatchContextReturnsFalse() {
    let context = "calories: 1850 protein: 120 carbs: 200"
    let response = "You had 1850 calories and 120g protein."
    #expect(AIResponseCleaner.hasHallucinatedNumbers(response, context: context) == false)
}

@Test func hasHallucinatedNumbers_manyUnknownNumbersReturnsTrue() {
    let context = "weight: 70"
    let response = "You burned 3500 calories and walked 12000 steps covering 8500 meters."
    #expect(AIResponseCleaner.hasHallucinatedNumbers(response, context: context) == true)
}

@Test func hasHallucinatedNumbers_smallNumbersAllowed() {
    // Numbers 1-10 are always allowed (too common to flag)
    let context = "weight: 70"
    let response = "You did 3 sets of 8 reps."
    #expect(AIResponseCleaner.hasHallucinatedNumbers(response, context: context) == false)
}
