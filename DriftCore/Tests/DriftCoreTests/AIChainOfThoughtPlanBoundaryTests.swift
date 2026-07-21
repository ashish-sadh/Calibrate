import Testing
@testable import DriftCore

/// Tier 0 — deterministic query-to-context planning without executing fetch steps.
@Suite struct AIChainOfThoughtPlanBoundaryTests {
    @Test @MainActor func acknowledgmentsIgnoreCaseAndSurroundingPunctuation() {
        for query in ["OK", "...thank you...", "(Sounds Good)", "!!!AWESOME!!!"] {
            #expect(AIChainOfThought.plan(query: query, screen: .dashboard) == nil)
        }
    }

    @Test @MainActor func recognizedShortQueryRoutesBeforeGenericLengthGate() throws {
        let steps = try #require(AIChainOfThought.plan(query: "gym", screen: .dashboard))

        #expect(steps.map(\.label) == ["Looking at workouts...", "Checking recovery..."])
    }

    @Test @MainActor func weightCauseQuestionAddsMealContext() throws {
        let steps = try #require(
            AIChainOfThought.plan(query: "Why am I not losing weight?", screen: .weight)
        )

        #expect(steps.map(\.label) == ["Analyzing weight trend...", "Checking your meals..."])
    }

    @Test @MainActor func multiDomainQueryKeepsStableContextOrder() throws {
        let steps = try #require(
            AIChainOfThought.plan(
                query: "Could fasting affect my sleep and blood sugar?",
                screen: .dashboard
            )
        )

        #expect(steps.map(\.label) == [
            "Checking your meals...",
            "Looking at your sleep...",
            "Reading glucose data...",
        ])
    }

    @Test @MainActor func nutritionLookupTakesPrecedenceOverGeneralFoodContext() throws {
        let steps = try #require(
            AIChainOfThought.plan(query: "How many calories in a banana?", screen: .food)
        )

        #expect(steps.map(\.label) == ["Looking up nutrition..."])
    }

    @Test @MainActor func unmatchedQueryUsesScreenFallbackExceptOnConfigurationScreens() throws {
        let weightSteps = try #require(
            AIChainOfThought.plan(query: "Tell me something useful", screen: .weight)
        )

        #expect(weightSteps.map(\.label) == ["Checking your day...", "Checking weight..."])
        #expect(AIChainOfThought.plan(query: "Tell me something useful", screen: .settings) == nil)
        #expect(AIChainOfThought.plan(query: "Tell me something useful", screen: .algorithm) == nil)
    }
}
