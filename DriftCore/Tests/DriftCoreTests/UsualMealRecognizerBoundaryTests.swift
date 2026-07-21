import Foundation
@testable import DriftCore
import Testing

/// Tier 0 — deterministic normalization and inference boundaries for usual-meal recall.
@Suite struct UsualMealRecognizerBoundaryTests {
    @Test func matchingIgnoresOuterWhitespaceAndLetterCase() {
        #expect(UsualMealRecognizer.match("  LOG MY USUAL LUNCH\n") == .lunch)
        #expect(UsualMealRecognizer.match("\tMy Regular Dinner Please  ") == .dinner)
    }

    @Test func explicitMealSlotOverridesTimeInferenceAndMessageLength() {
        let morning = date(atHour: 7)

        #expect(
            UsualMealRecognizer.match(
                "please log my usual dinner with the standard sides again",
                now: morning
            ) == .dinner
        )
    }

    @Test func bareUsualFollowsEveryMealTypeHourBoundary() {
        let cases: [(hour: Int, expected: MealType)] = [
            (4, .snack),
            (5, .breakfast),
            (9, .breakfast),
            (10, .lunch),
            (14, .lunch),
            (15, .snack),
            (17, .snack),
            (18, .dinner),
            (21, .dinner),
            (22, .snack),
        ]

        for testCase in cases {
            #expect(
                UsualMealRecognizer.match("the usual", now: date(atHour: testCase.hour))
                    == testCase.expected
            )
        }
    }

    @Test func regularMealCanInferWhileSpecificRegularFoodFallsThrough() {
        let lunch = date(atHour: 12)

        #expect(UsualMealRecognizer.match("log my regular meal", now: lunch) == .lunch)
        #expect(UsualMealRecognizer.match("log my regular protein shake with banana", now: lunch) == nil)
    }

    @Test func informationQuestionPrefixesBlockRecallWithoutQuestionMark() {
        let prompts = [
            "which usual lunch do I have",
            "when is my regular dinner",
            "what is my usual breakfast",
            "how nutritious is my usual snack",
        ]

        for prompt in prompts {
            #expect(UsualMealRecognizer.match(prompt) == nil)
        }
    }

    private func date(atHour hour: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 7, day: 21, hour: hour)
        )!
    }
}
