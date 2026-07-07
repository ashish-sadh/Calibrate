import Testing
@testable import DriftCore

/// Tier-0 — pins the nudge→Coach seed contract (#928): the prompt must carry
/// the nudge's real data (supplement names, day counts) verbatim so the Coach
/// opens on the user's actual state, never a cold generic turn.
struct NudgeCoachSeedTests {

    @Test func seedCarriesSupplementContext() {
        let prompt = NudgeCoachSeed.prompt(
            title: "Supplements missed",
            detail: "Creatine, Electrolytes — not taken in 3+ days")
        #expect(prompt.contains("Creatine"))
        #expect(prompt.contains("Electrolytes"))
        #expect(prompt.contains("3+ days"))
        #expect(prompt.contains("Supplements missed"))
    }

    @Test func seedReadsAsUserQuestion() {
        let prompt = NudgeCoachSeed.prompt(
            title: "Protein below target 3 days running",
            detail: "Avg 90g vs goal 130g.")
        #expect(prompt.hasSuffix("What should I do?"))
    }

    @Test func seedWithEmptyDetailHasNoDanglingSeparator() {
        let prompt = NudgeCoachSeed.prompt(title: "Log your weight", detail: "")
        #expect(prompt == "Log your weight. What should I do?")
        #expect(!prompt.contains("—"))
    }
}
