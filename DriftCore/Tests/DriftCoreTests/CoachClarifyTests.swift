import Foundation
@testable import DriftCore
import Testing

// "add 20 more calories" (a calorie amount with no food) must NOT food-search —
// the parser bails so the coach asks a follow-up. #coach-clarify

@Test func parserBailsOnCalorieWithoutFood() {
    #expect(AIActionExecutor.parseFoodIntent("add 20 more calories") == nil)
    #expect(AIActionExecutor.parseFoodIntent("log 200 calories") == nil)
    #expect(AIActionExecutor.parseFoodIntent("add some more calories") == nil)
}

@Test func parserStillParsesRealFoods() {
    #expect(AIActionExecutor.parseFoodIntent("add 20g chicken") != nil)
    #expect(AIActionExecutor.parseFoodIntent("ate 2 eggs") != nil)
    #expect(AIActionExecutor.parseFoodIntent("log extra cheesy pizza") != nil)   // guard not over-broad
}

@Test func isFoodNameVacuousDetectsNonFood() {
    #expect(AIActionExecutor.isFoodNameVacuous("more calories"))
    #expect(AIActionExecutor.isFoodNameVacuous("calories"))
    #expect(AIActionExecutor.isFoodNameVacuous("200"))
    #expect(AIActionExecutor.isFoodNameVacuous("some more"))
    #expect(!AIActionExecutor.isFoodNameVacuous("chicken"))
    #expect(!AIActionExecutor.isFoodNameVacuous("extra cheese"))   // "cheese" is a real food word
}

@Test func multiFoodDropsVacuousPart() {
    let intents = AIActionExecutor.parseMultiFoodIntent("log chicken and rice and more calories")
    #expect(intents?.count == 2)
    #expect(intents?.contains { $0.query.contains("calor") } == false)
}
