import Foundation
@testable import DriftCore
import Testing

// "log my usual lunch" recall recognizer. #usual-meal

@Test func recognizesExplicitSlot() {
    #expect(UsualMealRecognizer.match("log my usual lunch") == .lunch)
    #expect(UsualMealRecognizer.match("add my usual breakfast") == .breakfast)
    #expect(UsualMealRecognizer.match("the usual dinner") == .dinner)
    #expect(UsualMealRecognizer.match("my regular lunch please") == .lunch)
    #expect(UsualMealRecognizer.match("track my usual snack") == .snack)
}

@Test func bareUsualInfersFromHour() {
    let noonish = Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: Date())!
    #expect(UsualMealRecognizer.match("log my usual", now: noonish) == .lunch)
    #expect(UsualMealRecognizer.match("the usual", now: noonish) == .lunch)
    let morning = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
    #expect(UsualMealRecognizer.match("usual meal", now: morning) == .breakfast)
}

@Test func ignoresNonRecallAndQuestions() {
    #expect(UsualMealRecognizer.match("log 2 rotis and dal") == nil)
    #expect(UsualMealRecognizer.match("what's my usual lunch?") == nil)
    #expect(UsualMealRecognizer.match("how many calories in my usual lunch") == nil)
    #expect(UsualMealRecognizer.match("hello") == nil)
}

@Test func specificUsualFoodFallsThrough() {
    // "log my usual protein shake" is a specific food, not a whole-meal recall.
    #expect(UsualMealRecognizer.match("log my usual protein shake with banana") == nil)
}
