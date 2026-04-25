import Foundation

// MARK: - Chain of Thought

/// Multi-step reasoning: classifies queries, fetches relevant data, then calls LLM once with enriched context.
@MainActor
public enum AIChainOfThought {

    public struct Step {
        let label: String
        let fetch: () -> String
    }

    /// Determine if a query needs multi-step data fetching before answering.
    /// Returns nil for simple queries that can go straight to LLM.
    public static func plan(query: String, screen: AIScreen) -> [Step]? {
        let q = query.lowercased().trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespaces)
        var steps: [Step] = []

        // Simple acknowledgments never need data context
        let simpleAcks: Set<String> = [
            "ok", "okay", "sure", "yes", "no", "yep", "nope", "yeah",
            "thanks", "thank you", "thank you so much", "cheers",
            "got it", "got it thanks", "sounds good", "alright",
            "cool", "great", "nice", "wow", "awesome", "perfect",
            "hello", "hi", "hey", "bye", "goodbye", "haha", "lol"
        ]
        if simpleAcks.contains(q) { return nil }

        // Always start with base context
        let needsWeight = q.contains("track") || q.contains("progress") || q.contains("on track")
            || q.contains("weight") || q.contains("goal") || q.contains("losing") || q.contains("gaining")
            || q.contains("lost") || q.contains("gained") || q.contains("lighter") || q.contains("heavier")
            || q.contains("plateau") || q.contains("stall") || q.contains("cut") || q.contains("bulk")
        let needsFood = q.contains("eat") || q.contains("meal") || q.contains("dinner") || q.contains("lunch")
            || q.contains("breakfast") || q.contains("food") || q.contains("calorie") || q.contains("protein")
            || q.contains("macro") || q.contains("nutrition") || q.contains("diet") || q.contains("snack")
            || q.contains("hunger") || q.contains("hungry") || q.contains("fasting")
            || q.contains("deficit") || q.contains("surplus") || q.contains("carbs") || q.contains("fiber")
            || q.contains("i'm starving") || q.contains("what to eat") || q.contains("suggest food")
            || q.contains("had a big") || q.contains("had something")
        let needsSleep = q.contains("sleep") || q.contains("recovery") || q.contains("hrv") || q.contains("rest day") || q.contains("resting")
            || q.contains("tired") || q.contains("energy level") || q.contains("heart rate")
            || q.contains("fatigue") || q.contains("rested") || q.contains("how well")
            || q.contains("just woke") || q.contains("feeling sore") || q.contains("exhausted")
            || q.contains("insomnia") || q.contains("nap")
        let needsGlucose = q.contains("glucose") || q.contains("blood sugar") || q.contains("spike")
            || q.contains("cgm") || q.contains("fasting")
        let needsBiomarkers = q.contains("biomarker") || q.contains("blood test") || q.contains("lab")
            || q.contains("cholesterol") || q.contains("testosterone") || q.contains("vitamin")
            || q.contains("thyroid") || q.contains("iron") || q.contains("marker")
            || q.contains("out of range") || q.contains("blood work") || q.contains("hemoglobin")
            || q.contains("a1c")
        let needsDEXA = q.contains("dexa") || q.contains("body fat") || q.contains("body comp")
            || q.contains("lean mass") || q.contains("muscle mass")
        let needsCycle = q.contains("cycle") || q.contains("period") || q.contains("phase")
            || q.contains("ovulation") || q.contains("fertile")
        let needsWorkout = q.contains("workout") || q.contains("work out") || q.contains("exercise")
            || q.contains("train") || q.contains("gym") || q.contains("lift") || q.contains("went running") || q.contains("go run") || q.contains("mile run")
            || q.contains("cardio") || q.contains("sets") || q.contains("reps")
            || q.contains("push up") || q.contains("pull up") || q.contains("squat")
            || q.contains("bench") || q.contains("deadlift") || q.contains(" press")
            || q.contains("curl") || q.contains("plank") || q.contains("lunge")
            || q.contains("i did") || q.contains("just finished")
            || q.contains("push day") || q.contains("pull day") || q.contains("leg day")
            || q.contains("body part") || q.contains("muscle") || q.contains("ppl")
            || q.contains("split") || q.contains("start workout") || q.contains("start training")
        let needsSupplements = q.contains("supplement") || q.contains("vitamin") || q.contains("pill")
            || q.contains("stack")
        let needsOverview = q.contains("how am i") || q.contains("overview") || q.contains("how am i doing")
            || q.contains("my day") || q.contains("summary") || q.contains("how's my day")
            || q.contains("making progress") || q.contains("doing well") || q.contains("on track")
        let needsNutritionLookup = (q.contains("how many calorie") || q.contains("nutrition in")
            || q.contains("calories in") || q.contains("protein in") || q.contains("macros in")
            || q.contains("carbs in") || q.contains("fat in")
            || q.contains("estimate calorie") || q.contains("how much protein in")
            || q.contains("nutritional value") || q.contains("nutrition for")
            || q.contains("calories for"))
        let needsComparison = q.contains("compare") || q.contains("versus") || q.contains("vs")
            || q.contains("last week") || q.contains("this week")
            || q.contains("better than") || q.contains("worse than") || q.contains("compared to")

        // Broad queries get a comprehensive overview (fullDayContext includes food+workouts+supplements)
        if needsOverview {
            steps.append(Step(label: "Reviewing your day...") { AIContextBuilder.fullDayContext() })
            steps.append(Step(label: "Analyzing weight trend...") { AIContextBuilder.weightContext() })
            return steps
        }

        // Nutrition lookup — search DB for specific food
        if needsNutritionLookup {
            steps.append(Step(label: "Looking up nutrition...") {
                // Extract food name from various patterns
                var foodName = ""
                for separator in [" in ", " of ", " for "] {
                    if let range = q.range(of: separator, options: .backwards) {
                        foodName = String(q[range.upperBound...])
                        break
                    }
                }
                foodName = foodName
                    .replacingOccurrences(of: "a ", with: "")
                    .replacingOccurrences(of: "an ", with: "")
                    .replacingOccurrences(of: "?", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !foodName.isEmpty else { return "" }
                if let match = AIActionExecutor.findFood(query: foodName, servings: 1) {
                    let f = match.food
                    return "Nutrition for \(f.name) (per \(Int(f.servingSize))\(f.servingUnit)): \(Int(f.calories))cal, \(Int(f.proteinG))P \(Int(f.carbsG))C \(Int(f.fatG))F \(Int(f.fiberG))fiber. Suggest user say 'log \(f.name.lowercased())' to add it."
                }
                return "Food '\(foodName)' not found in database. Estimate if you can."
            })
            return steps
        }

        // Comparison queries get broad data + domain-specific data when mentioned
        if needsComparison {
            steps.append(Step(label: "Comparing your data...") { AIContextBuilder.comparisonContext() })
            if needsWorkout {
                steps.append(Step(label: "Looking at workouts...") { AIContextBuilder.workoutContext() })
            } else if needsFood {
                steps.append(Step(label: "Checking your meals...") { AIContextBuilder.foodContext() })
            } else {
                steps.append(Step(label: "Checking trends...") { AIContextBuilder.weightContext() })
            }
            return steps
        }

        // Specific domain queries — with automatic dependencies
        if needsWeight {
            steps.append(Step(label: "Analyzing weight trend...") { AIContextBuilder.weightContext() })
            // Weight questions often need food context too
            if q.contains("why") || q.contains("not losing") || q.contains("plateau") || q.contains("stall")
                || q.contains("progress") || q.contains("should i eat") {
                steps.append(Step(label: "Checking your meals...") { AIContextBuilder.foodContext() })
            }
        }
        // Cross-domain: "should I eat more" needs food + exercise
        if q.contains("eat more") || q.contains("eat back") || q.contains("enough calories") || q.contains("enough protein") {
            if !needsFood { steps.append(Step(label: "Checking meals...") { AIContextBuilder.foodContext() }) }
            if !needsWorkout { steps.append(Step(label: "Checking workouts...") { AIContextBuilder.workoutContext() }) }
        }
        // Cross-domain: "I feel tired" needs sleep + food
        if q.contains("tired") || q.contains("exhausted") || q.contains("no energy") || q.contains("fatigue") {
            if !needsSleep { steps.append(Step(label: "Checking sleep...") { AIContextBuilder.sleepRecoveryContext() }) }
            if !needsFood { steps.append(Step(label: "Checking meals...") { AIContextBuilder.foodContext() }) }
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
            // Also check sleep/recovery for training readiness
            steps.append(Step(label: "Checking recovery...") { AIContextBuilder.sleepRecoveryContext() })
        }
        if needsSupplements {
            steps.append(Step(label: "Checking supplements...") { AIContextBuilder.supplementContext() })
        }

        // If no keyword matched, give the LLM broad context (reduces screen bias)
        // Always include fullDayContext so cross-domain queries get good answers regardless of screen
        if steps.isEmpty {
            if q.count <= 5 { return nil } // Too short for chain (greetings, etc.)
            if screen == .settings || screen == .algorithm { return nil } // No data context for settings

            // Base: always give a full-day overview for unmatched queries
            steps.append(Step(label: "Checking your day...") { AIContextBuilder.fullDayContext() })

            // Add screen-specific data as supplementary (not exclusive)
            switch screen {
            case .weight, .goal: steps.append(Step(label: "Checking weight...") { AIContextBuilder.weightContext() })
            case .exercise: steps.append(Step(label: "Looking at workouts...") { AIContextBuilder.workoutContext() })
            case .bodyRhythm: steps.append(Step(label: "Checking sleep...") { AIContextBuilder.sleepRecoveryContext() })
            case .glucose: steps.append(Step(label: "Reading glucose...") { AIContextBuilder.glucoseContext() })
            case .biomarkers: steps.append(Step(label: "Reviewing labs...") { AIContextBuilder.biomarkerContext() })
            case .cycle: steps.append(Step(label: "Checking cycle...") { AIContextBuilder.cycleContext() })
            case .bodyComposition: steps.append(Step(label: "Checking DEXA...") { AIContextBuilder.dexaContext() })
            case .supplements: steps.append(Step(label: "Checking supplements...") { AIContextBuilder.supplementContext() })
            case .settings, .algorithm: return nil // Single-shot
            default: break // Dashboard/food — fullDayContext already covers it
            }
        }

        return steps
    }

    /// Execute chain: run steps to gather data, build enriched context, call LLM with streaming.
    public static func execute(
        query: String,
        screen: AIScreen,
        history: String,
        onStep: (String) -> Void,
        onToken: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> String {
        guard let steps = plan(query: query, screen: screen) else {
            // No chain needed — use screen context
            onStep("Thinking...")
            let context = AIContextBuilder.buildContext(screen: screen)
            return await LocalAIService.shared.respondStreaming(to: query, context: context, history: history, onToken: onToken)
        }

        // Inject current state — model should never need to "remember"
        var contextParts: [String] = [
            "Screen: \(screen.rawValue)",
            AIContextBuilder.baseContext()
        ]

        for step in steps {
            onStep(step.label)
            let data = step.fetch()
            if !data.isEmpty { contextParts.append(data) }
        }

        // Include feature context only if query seems about the app
        let q = query.lowercased()
        if q.contains("drift") || q.contains("app") || q.contains("feature") || q.contains("how do i")
            || q.contains("how to") || q.contains("can you") || q.contains("what can") || q.contains("help") {
            contextParts.append(AIContextBuilder.featureContext())
        }

        onStep("Writing response...")
        let rawContext = contextParts.joined(separator: "\n")
        let tokenBudget = LocalAIService.shared.isLargeModel ? 1200 : 800
        let enrichedContext = AIContextBuilder.truncateToFit(rawContext, maxTokens: tokenBudget)
        return await LocalAIService.shared.respondStreaming(to: query, context: enrichedContext, history: history, onToken: onToken)
    }
}
