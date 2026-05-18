import Foundation
@testable import DriftCore
import Testing

// MARK: - Acceptance criteria (from issue #384)

@Test func splitsFoodAndWeight() {
    let result = MultiIntentSplitter.split("I had eggs and logged 70kg")
    #expect(result == ["I had eggs", "logged 70kg"])
}

@Test func splitsSupplementAndWeight() {
    let result = MultiIntentSplitter.split("mark creatine and update my weight")
    #expect(result == ["mark creatine", "update my weight"])
}

@Test func doesNotSplitSameDomainFoodMultiItem() {
    // "rice" alone has no domain signal — prevents false split
    #expect(MultiIntentSplitter.split("I had chicken and rice") == nil)
}

// MARK: - split() — positive cases

@Test func splitsFoodAndWeightWithMealContext() {
    let result = MultiIntentSplitter.split("I had dal for lunch and weighed 68 kg")
    #expect(result?.count == 2)
    #expect(result?[0] == "I had dal for lunch")
    #expect(result?[1] == "weighed 68 kg")
}

@Test func splitsThreeDomains() {
    let result = MultiIntentSplitter.split("had eggs and took creatine and logged 70kg")
    #expect(result?.count == 3)
}

@Test func splitsFoodAndWeightWithLbsUnit() {
    let result = MultiIntentSplitter.split("ate biryani and I weigh 165 lbs")
    #expect(result?.count == 2)
}

@Test func splitsVitaminAndWeight() {
    let result = MultiIntentSplitter.split("took vitamin d and update weight to 72")
    #expect(result?.count == 2)
}

@Test func splitIsCaseInsensitiveOnAnd() {
    let result = MultiIntentSplitter.split("I had eggs AND logged 70kg")
    #expect(result?.count == 2)
}

// MARK: - split() — negative cases (no split)

@Test func noSplitWithoutAnd() {
    #expect(MultiIntentSplitter.split("I had eggs for breakfast") == nil)
    #expect(MultiIntentSplitter.split("log 2 eggs") == nil)
    #expect(MultiIntentSplitter.split("weighed 75kg") == nil)
}

@Test func noSplitBareMultiItemFood() {
    #expect(MultiIntentSplitter.split("eggs and toast") == nil)
    #expect(MultiIntentSplitter.split("rice and dal") == nil)
}

@Test func noSplitCompoundFoodNameFishAndChips() {
    // Acceptance criterion (#688): "fish and chips" is a compound food name —
    // splitter must NOT split it. Both "I had fish and chips" and bare
    // "fish and chips" stay as a single message; the LLM handles them as
    // one log_food call.
    #expect(MultiIntentSplitter.split("I had fish and chips") == nil)
    #expect(MultiIntentSplitter.split("fish and chips") == nil)
    #expect(MultiIntentSplitter.split("ate fish and chips for lunch") == nil)
}

@Test func noSplitMacAndCheeseStyleCompounds() {
    // Same shape as fish-and-chips: compound food names where neither
    // segment carries a domain signal on its own.
    #expect(MultiIntentSplitter.split("had mac and cheese") == nil)
    #expect(MultiIntentSplitter.split("peanut butter and jelly sandwich") == nil)
    #expect(MultiIntentSplitter.split("cookies and cream ice cream") == nil)
}

@Test func noSplitSameDomainSupplements() {
    #expect(MultiIntentSplitter.split("took vitamin d and creatine") == nil)
}

@Test func noSplitUnclassifiableSegment() {
    // "something" has no domain → don't split
    #expect(MultiIntentSplitter.split("I had eggs and something") == nil)
}

// MARK: - domain() — unit coverage

@Test func domainWeightByWord() {
    #expect(MultiIntentSplitter.domain(of: "update my weight") == "weight")
    #expect(MultiIntentSplitter.domain(of: "weighed 68 kg") == "weight")
    #expect(MultiIntentSplitter.domain(of: "scale says 165") == "weight")
}

@Test func domainWeightByUnit() {
    #expect(MultiIntentSplitter.domain(of: "logged 70kg") == "weight")
    #expect(MultiIntentSplitter.domain(of: "165 lbs") == "weight")
    #expect(MultiIntentSplitter.domain(of: "72.5 kg") == "weight")
}

@Test func domainFoodByEatingVerb() {
    #expect(MultiIntentSplitter.domain(of: "I had eggs") == "food")
    #expect(MultiIntentSplitter.domain(of: "ate biryani") == "food")
    #expect(MultiIntentSplitter.domain(of: "drank coffee") == "food")
}

@Test func domainFoodByLogVerb() {
    #expect(MultiIntentSplitter.domain(of: "log breakfast") == "food")
    #expect(MultiIntentSplitter.domain(of: "add 2 eggs") == "food")
    #expect(MultiIntentSplitter.domain(of: "track my food") == "food")
}

@Test func domainSupplementByName() {
    #expect(MultiIntentSplitter.domain(of: "mark creatine") == "supplement")
    #expect(MultiIntentSplitter.domain(of: "took vitamin d") == "supplement")
    #expect(MultiIntentSplitter.domain(of: "zinc tablet") == "supplement")
    #expect(MultiIntentSplitter.domain(of: "omega 3 capsule") == "supplement")
}

@Test func domainNilForBareNoun() {
    #expect(MultiIntentSplitter.domain(of: "rice") == nil)
    #expect(MultiIntentSplitter.domain(of: "chicken") == nil)
    #expect(MultiIntentSplitter.domain(of: "something") == nil)
}

@Test func domainWeightTakesPrecedenceOverLogVerb() {
    // "log weight 70kg" has "log " (food) AND weight unit — weight wins
    #expect(MultiIntentSplitter.domain(of: "log weight 70kg") == "weight")
}

// MARK: - v2 (#797): workout domain detection

@Test func domainWorkoutByGymVocabulary() {
    #expect(MultiIntentSplitter.domain(of: "went to the gym") == "workout")
    #expect(MultiIntentSplitter.domain(of: "did 30 min cardio") == "workout")
    #expect(MultiIntentSplitter.domain(of: "morning yoga session") == "workout")
}

@Test func domainWorkoutByLogVerbWithWorkoutNoun() {
    // "log my workout" has both "log " (food) and "workout" (workout) — workout wins
    #expect(MultiIntentSplitter.domain(of: "log my workout") == "workout")
    #expect(MultiIntentSplitter.domain(of: "track my workout today") == "workout")
}

@Test func domainWorkoutByLiftingMoves() {
    #expect(MultiIntentSplitter.domain(of: "did 3 sets of squats") == "workout")
    #expect(MultiIntentSplitter.domain(of: "deadlift PR today") == "workout")
    #expect(MultiIntentSplitter.domain(of: "bench press session") == "workout")
}

@Test func domainWorkoutByBodyPartDay() {
    #expect(MultiIntentSplitter.domain(of: "leg day") == "workout")
    #expect(MultiIntentSplitter.domain(of: "push day at 6am") == "workout")
    #expect(MultiIntentSplitter.domain(of: "chest day done") == "workout")
}

@Test func domainWorkoutByDidPhrase() {
    #expect(MultiIntentSplitter.domain(of: "did chest today") == "workout")
    #expect(MultiIntentSplitter.domain(of: "did pull yesterday") == "workout")
}

@Test func domainWorkoutDoesNotMatchFoodTerms() {
    // Make sure workout vocab doesn't accidentally match common food phrases
    #expect(MultiIntentSplitter.domain(of: "I had rice") == "food")
    #expect(MultiIntentSplitter.domain(of: "ate paneer") == "food")
}

// MARK: - v2 (#797): temporal domain + isTemporal()

@Test func isTemporalDetectsRemindMe() {
    #expect(MultiIntentSplitter.isTemporal("remind me to log dinner") == true)
    #expect(MultiIntentSplitter.isTemporal("can you remind me at 7pm") == true)
}

@Test func isTemporalDetectsRemember() {
    #expect(MultiIntentSplitter.isTemporal("remember to take vitamin") == true)
    #expect(MultiIntentSplitter.isTemporal("set a reminder for me") == true)
}

@Test func isTemporalRejectsNonScheduling() {
    // Time-of-day mentions alone are NOT temporal scheduling intent
    #expect(MultiIntentSplitter.isTemporal("I ate at 7pm") == false)
    #expect(MultiIntentSplitter.isTemporal("dinner tomorrow") == false)
    #expect(MultiIntentSplitter.isTemporal("log breakfast") == false)
}

@Test func domainTemporalWinsOverFood() {
    // "remind me to log dinner" has "log " (food) but "remind me" makes it temporal
    #expect(MultiIntentSplitter.domain(of: "remind me to log dinner at 7pm") == "temporal")
    #expect(MultiIntentSplitter.domain(of: "remember to take creatine") == "temporal")
}

// MARK: - v2 (#797): compound splitting via strong separators

@Test func splitsCompoundFoodAndWorkoutViaAlsoSeparator() {
    let result = MultiIntentSplitter.split("log eggs and toast, also log my workout")
    #expect(result?.count == 2)
    #expect(result?[0] == "log eggs and toast")
    #expect(result?[1] == "log my workout")
}

@Test func splitsCompoundViaThenSeparator() {
    let result = MultiIntentSplitter.split("log eggs and toast, then did pushups")
    #expect(result?.count == 2)
    #expect(result?[0] == "log eggs and toast")
    #expect(result?[1] == "did pushups")
}

@Test func splitsCompoundViaSemicolonAlso() {
    let result = MultiIntentSplitter.split("ate biryani; also did cardio")
    #expect(result?.count == 2)
    #expect(result?[1] == "did cardio")
}

@Test func splitsCompoundRefinesInnerAnd() {
    // "I had eggs and weighed 70kg" is a fine-grain split inside the first
    // coarse segment; the strong separator triggers the second segment.
    let result = MultiIntentSplitter.split("I had eggs and weighed 70kg, also did pushups")
    #expect(result?.count == 3)
    #expect(result?[0] == "I had eggs")
    #expect(result?[1] == "weighed 70kg")
    #expect(result?[2] == "did pushups")
}

@Test func noSplitCompoundWithoutDomainSignal() {
    // Strong separator present but neither segment has a domain — don't split
    #expect(MultiIntentSplitter.split("going to the store, also picking up mail") == nil)
}

@Test func noSplitCompoundWithSameDomain() {
    // Strong separator + same-domain segments + no temporal → don't split.
    // The LLM handles "log breakfast, then log dinner" as one query.
    #expect(MultiIntentSplitter.split("log breakfast, then log dinner") == nil)
}

@Test func noSplitCompoundFoodNameWithLeadingClause() {
    // Compound food name on one side, no real second-domain on the other
    #expect(MultiIntentSplitter.split("rice and dal, also fetched mail") == nil)
}

// MARK: - v2 (#797): temporal multi-intent

@Test func splitsFoodAndTemporal() {
    let result = MultiIntentSplitter.split("log my breakfast and remind me to log dinner at 7pm")
    #expect(result?.count == 2)
    #expect(result?[0] == "log my breakfast")
    #expect(result?[1] == "remind me to log dinner at 7pm")
}

@Test func splitsSameDomainAllowedWhenOneSegmentTemporal() {
    // Both segments look food-y to the v1 splitter ("log breakfast" + "log
    // dinner"), but the second is temporal → temporal exception fires and
    // the split proceeds.
    let result = MultiIntentSplitter.split("log breakfast and remember to log dinner later")
    #expect(result?.count == 2)
}

@Test func splitsCompoundFoodAndTemporalViaStrongSeparator() {
    let result = MultiIntentSplitter.split("log my breakfast, also remind me to take vitamin at 9pm")
    #expect(result?.count == 2)
    #expect(result?[1] == "remind me to take vitamin at 9pm")
}

// MARK: - v2 (#797): handling() dispatch

@Test func handlingExecutesNonTemporalSegment() {
    #expect(MultiIntentSplitter.handling(for: "log breakfast") == .execute)
    #expect(MultiIntentSplitter.handling(for: "weighed 70kg") == .execute)
    #expect(MultiIntentSplitter.handling(for: "did pushups") == .execute)
}

@Test func handlingSkipsTemporalWithTransparentMessage() {
    let result = MultiIntentSplitter.handling(for: "remind me to log dinner at 7pm")
    if case .skipTemporal(let message) = result {
        #expect(message.contains("don't have reminders"))
        #expect(message.contains("remind me to log dinner at 7pm"))
    } else {
        Issue.record("expected .skipTemporal for temporal sub-query")
    }
}

@Test func temporalSkipMessageQuotesUserText() {
    let msg = MultiIntentSplitter.temporalSkipMessage(for: "remember to take vitamin")
    #expect(msg.contains("\"remember to take vitamin\""))
    #expect(msg.contains("manually"))
}
