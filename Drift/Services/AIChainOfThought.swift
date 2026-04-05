import Foundation

// MARK: - Screen Tracking

/// Tracks which screen the user is currently viewing for context-aware AI responses.
@MainActor @Observable
final class AIScreenTracker {
    static let shared = AIScreenTracker()
    var currentScreen: AIScreen = .dashboard
}

/// All screens the AI can be aware of.
enum AIScreen: String, Sendable {
    case dashboard, weight, food, exercise
    case bodyRhythm, cycle, supplements, bodyComposition, glucose, biomarkers
    case goal, settings, algorithm
}

// MARK: - Chain of Thought

/// Multi-step reasoning: classifies queries, fetches relevant data, then calls LLM once with enriched context.
@MainActor
enum AIChainOfThought {

    struct Step {
        let label: String
        let fetch: () -> String
    }

    /// Determine if a query needs multi-step data fetching before answering.
    /// Returns nil for simple queries that can go straight to LLM.
    static func plan(query: String, screen: AIScreen) -> [Step]? {
        let q = query.lowercased()
        var steps: [Step] = []

        // Always start with base context
        let needsWeight = q.contains("track") || q.contains("progress") || q.contains("on track")
            || q.contains("weight") || q.contains("goal") || q.contains("losing") || q.contains("gaining")
        let needsFood = q.contains("eat") || q.contains("meal") || q.contains("dinner") || q.contains("lunch")
            || q.contains("breakfast") || q.contains("food") || q.contains("calorie") || q.contains("protein")
            || q.contains("macro") || q.contains("nutrition") || q.contains("diet")
        let needsSleep = q.contains("sleep") || q.contains("recovery") || q.contains("hrv") || q.contains("rest")
            || q.contains("tired") || q.contains("energy")
        let needsGlucose = q.contains("glucose") || q.contains("blood sugar") || q.contains("spike")
            || q.contains("cgm") || q.contains("fasting")
        let needsBiomarkers = q.contains("biomarker") || q.contains("blood test") || q.contains("lab")
            || q.contains("cholesterol") || q.contains("testosterone") || q.contains("vitamin")
            || q.contains("thyroid") || q.contains("iron")
        let needsDEXA = q.contains("dexa") || q.contains("body fat") || q.contains("body comp")
            || q.contains("lean mass") || q.contains("muscle mass")
        let needsCycle = q.contains("cycle") || q.contains("period") || q.contains("phase")
            || q.contains("ovulation") || q.contains("fertile")
        let needsWorkout = q.contains("workout") || q.contains("exercise") || q.contains("train")
            || q.contains("gym") || q.contains("lift")
        let needsSupplements = q.contains("supplement") || q.contains("vitamin") || q.contains("pill")
            || q.contains("stack")
        let needsOverview = q.contains("how am i") || q.contains("overview") || q.contains("doing")
            || q.contains("my day") || q.contains("summary")

        // Broad queries get everything relevant
        if needsOverview {
            steps.append(Step(label: "Checking your meals...") { AIContextBuilder.foodContext() })
            steps.append(Step(label: "Analyzing weight trend...") { AIContextBuilder.weightContext() })
            steps.append(Step(label: "Reviewing your day...") { AIContextBuilder.fullDayContext() })
            return steps
        }

        // Specific domain queries
        if needsWeight {
            steps.append(Step(label: "Analyzing weight trend...") { AIContextBuilder.weightContext() })
        }
        if needsFood {
            steps.append(Step(label: "Checking your meals...") { AIContextBuilder.foodContext() })
        }
        if needsSleep {
            steps.append(Step(label: "Looking at your sleep...") { AIContextBuilder.sleepRecoveryContext() })
        }
        if needsGlucose {
            steps.append(Step(label: "Reading glucose data...") { AIContextBuilder.glucoseContext() })
        }
        if needsBiomarkers {
            steps.append(Step(label: "Reviewing lab results...") { AIContextBuilder.biomarkerContext() })
        }
        if needsDEXA {
            steps.append(Step(label: "Checking body composition...") { AIContextBuilder.dexaContext() })
        }
        if needsCycle {
            steps.append(Step(label: "Checking cycle data...") { AIContextBuilder.cycleContext() })
        }
        if needsWorkout {
            steps.append(Step(label: "Looking at workouts...") { AIContextBuilder.workoutContext() })
        }
        if needsSupplements {
            steps.append(Step(label: "Checking supplements...") { AIContextBuilder.supplementContext() })
        }

        // If no specific domain matched, use screen-aware context
        if steps.isEmpty {
            return nil // Simple query — single-shot LLM
        }

        return steps
    }

    /// Execute chain: run steps to gather data, build enriched context, call LLM once.
    static func execute(
        query: String,
        screen: AIScreen,
        history: String,
        onStep: (String) -> Void
    ) async -> String {
        guard let steps = plan(query: query, screen: screen) else {
            // No chain needed — use screen context
            onStep("Thinking...")
            let context = AIContextBuilder.buildContext(screen: screen)
            return await LocalAIService.shared.respond(to: query, context: context, history: history)
        }

        // Gather data from each step
        var contextParts: [String] = [AIContextBuilder.baseContext()]

        for step in steps {
            onStep(step.label)
            let data = step.fetch()
            if !data.isEmpty { contextParts.append(data) }
        }

        // Always include feature context
        contextParts.append(AIContextBuilder.featureContext())

        onStep("Writing response...")
        let enrichedContext = contextParts.joined(separator: "\n")
        return await LocalAIService.shared.respond(to: query, context: enrichedContext, history: history)
    }
}
