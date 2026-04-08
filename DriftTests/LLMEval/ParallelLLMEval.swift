import XCTest
@testable import Drift

/// Runs all 3 model evals in parallel using TaskGroup.
/// Each model gets its own LlamaCppBackend with 4 threads (14 cores / 3 models = ~4 each).
/// Deep eval: DRIFT_DEEP_EVAL=1 xcodebuild test -only-testing:'DriftLLMEvalTests/ParallelLLMEval'
final class ParallelLLMEval: XCTestCase {

    private struct ModelSpec {
        let path: String
        let name: String
        let isGemma: Bool
    }

    private static let specs: [ModelSpec] = [
        ModelSpec(path: "/tmp/qwen2.5-1.5b-instruct-q4_k_m.gguf", name: "Qwen2.5-1.5B", isGemma: false),
        ModelSpec(path: "/tmp/gemma-4-e2b-q4_k_m.gguf", name: "Gemma4-2B", isGemma: true),
        ModelSpec(path: "/tmp/qwen3-1.7b-q4_k_m.gguf", name: "Qwen3-1.7B", isGemma: false),
    ]

    private static let threadsPerModel = 4  // 14 cores / 3 models, leave 2 for OS

    // Shared queries — same across all models for fair comparison
    private static let foodLogQueries: [(String, String)] = [
        ("I had 2 eggs", "log_food"),
        ("log chicken breast", "log_food"),
        ("ate a banana for lunch", "log_food"),
        ("had dal and rice", "log_food"),
        ("log a protein shake", "log_food"),
        ("I just had a samosa", "log_food"),
        ("ate 3 rotis for dinner", "log_food"),
        ("log oatmeal for breakfast", "log_food"),
        ("had a bowl of soup", "log_food"),
        ("I drank a coffee", "log_food"),
    ]

    private static let foodQuestionQueries: [(String, String)] = [
        ("calories left?", "food_info"),
        ("how much protein in banana", "food_info"),
        ("what should I eat for dinner", "food_info"),
        ("calories in a samosa", "food_info"),
        ("suggest something high protein", "food_info"),
        ("am I eating too much", "food_info"),
        ("what did I eat today", "food_info"),
        ("I'm hungry what should I have", "food_info"),
        ("how's my protein intake", "food_info"),
        ("is my diet balanced", "food_info"),
    ]

    private static let weightQueries: [(String, String)] = [
        ("I weigh 165 lbs", "log_weight"),
        ("my weight is 75 kg", "log_weight"),
        ("how's my weight trend", "weight_info"),
        ("am I on track to reach my goal", "weight_info"),
        ("am I losing weight", "weight_info"),
        ("scale says 170 today", "log_weight"),
        ("what's my goal progress", "weight_info"),
        ("weighed in at 80 kg", "log_weight"),
        ("how fast am I losing", "weight_info"),
        ("what's my body fat", "weight_info"),
    ]

    private static let exerciseQueries: [(String, String)] = [
        ("what should I train today", "exercise_info"),
        ("start push day", "start_workout"),
        ("start chest workout", "start_workout"),
        ("I want to do legs today", "start_workout"),
        ("build me a back workout", "start_workout"),
        ("what muscle haven't I trained", "exercise_info"),
        ("am I making progress on bench", "exercise_info"),
        ("start pull day", "start_workout"),
        ("I want to work out", "exercise_info"),
        ("is my bench press improving", "exercise_info"),
    ]

    private func systemPrompt() -> String {
        """
        You help track food, weight, and workouts. \
        LOGGING (user ate/did something) → call log tool. \
        QUESTION (user asks about data) → call info tool. \
        CHAT (greeting, thanks) → respond naturally, no tool. \
        Never give health advice. Never invent numbers. \
        Examples: \
        "I had 2 eggs" → {"tool":"log_food","params":{"name":"eggs","amount":"2"}} \
        "calories left" → {"tool":"food_info","params":{}} \
        "how's my weight" → {"tool":"weight_info","params":{}} \
        "start chest workout" → {"tool":"start_workout","params":{"name":"chest"}} \
        "what should I train" → {"tool":"exercise_info","params":{}} \
        "how'd I sleep" → {"tool":"sleep_recovery","params":{}} \
        "thanks" → You're welcome! (no tool) \
        Tools:
        - log_food(name:string, amount:number) — User wants to LOG food they ate
        - food_info(query:string) — User asks ABOUT food: calories, protein, what to eat
        - log_weight(value:number, unit:string) — User wants to LOG body weight
        - weight_info() — User asks ABOUT weight: trend, goal, body fat
        - start_workout(name:string) — User wants to START a workout
        - exercise_info(exercise:string) — User asks ABOUT workouts: what to train, progress
        """
    }

    private func context() -> String {
        "Calories: 1200 eaten, 1800 target, 600 remaining\nMacros: 80P 150C 40F\nWeight: 165 lbs, -0.8/wk"
    }

    private static func runQueries(_ queries: [(String, String)], backend: LlamaCppBackend, label: String, modelName: String, sysPrompt: String, ctx: String) async -> (correct: Int, total: Int) {
        var correct = 0
        for (query, expected) in queries {
            let prompt = "Context about the user:\n\(ctx)\n\nUser: \(query)"
            let response = await backend.respond(to: prompt, systemPrompt: sysPrompt)
            let call = parseToolCallJSON(response)
            if call?.tool == expected {
                correct += 1
            } else {
                print("  ❌ [\(modelName)] \(label): '\(query)' → \(call?.tool ?? "none") (expected \(expected))")
            }
        }
        return (correct, queries.count)
    }

    // MARK: - Parallel Deep Eval

    func testParallelDeepEval() async throws {
        guard ProcessInfo.processInfo.environment["DRIFT_DEEP_EVAL"] != nil else {
            throw XCTSkip("Set DRIFT_DEEP_EVAL=1 to run parallel deep eval")
        }

        let available = Self.specs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !available.isEmpty else { throw XCTSkip("No models found at /tmp/") }

        print("═══ PARALLEL DEEP EVAL — \(available.count) models, \(Self.threadsPerModel) threads each ═══")
        let start = CFAbsoluteTimeGetCurrent()

        // Load all models (sequential — model loading is fast)
        var backends: [(LlamaCppBackend, String)] = []
        for spec in available {
            let b = LlamaCppBackend(modelPath: URL(fileURLWithPath: spec.path), threads: Self.threadsPerModel)
            try? b.loadSync()
            if b.isLoaded {
                backends.append((b, spec.name))
                print("  ✅ Loaded \(spec.name) (\(Self.threadsPerModel) threads)")
            }
        }

        guard !backends.isEmpty else { throw XCTSkip("No models could be loaded") }

        // Run all model evals in parallel
        let allQueries: [([(String, String)], String)] = [
            (Self.foodLogQueries, "Food Log"),
            (Self.foodQuestionQueries, "Food Q"),
            (Self.weightQueries, "Weight"),
            (Self.exerciseQueries, "Exercise"),
        ]

        // Each model runs all query categories concurrently with other models
        let sysPrompt = systemPrompt()
        let ctx = context()
        await withTaskGroup(of: (String, [(String, Int, Int)]).self) { group in
            for (backend, name) in backends {
                group.addTask {
                    var results: [(String, Int, Int)] = []
                    for (queries, label) in allQueries {
                        let r = await Self.runQueries(queries, backend: backend, label: label, modelName: name, sysPrompt: sysPrompt, ctx: ctx)
                        results.append((label, r.correct, r.total))
                    }
                    return (name, results)
                }
            }

            for await (name, results) in group {
                let totalCorrect = results.reduce(0) { $0 + $1.1 }
                let totalQueries = results.reduce(0) { $0 + $1.2 }
                print("\n📊 \(name) Results:")
                for (label, correct, total) in results {
                    let pct = total > 0 ? correct * 100 / total : 0
                    print("   \(label): \(correct)/\(total) (\(pct)%)")
                }
                print("   TOTAL: \(totalCorrect)/\(totalQueries) (\(totalQueries > 0 ? totalCorrect * 100 / totalQueries : 0)%)")
                XCTAssertGreaterThanOrEqual(totalCorrect, totalQueries / 4, "\(name) should get at least 25% correct")
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        print("\n═══ PARALLEL DEEP EVAL COMPLETE in \(String(format: "%.0f", elapsed))s ═══")
    }
}
