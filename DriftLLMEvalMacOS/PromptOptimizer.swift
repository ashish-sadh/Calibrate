import Foundation

// MARK: - Pipeline Config

/// Snapshot of all mutable parts of the AI pipeline.
/// The optimizer tries variants and keeps what scores highest.
struct PipelineConfig {
    var classifierPrompt: String
    var presentationPrompt: String
    var mutation: EvalMutation

    static func baseline(classifierPrompt: String, presentationPrompt: String) -> PipelineConfig {
        PipelineConfig(classifierPrompt: classifierPrompt,
                       presentationPrompt: presentationPrompt,
                       mutation: .baseline)
    }
}

// MARK: - Mutation

enum EvalMutation: CustomStringConvertible {
    case baseline
    case addClassifierExample(input: String, output: String)
    case addClassifierRule(clause: String)
    case rewritePresentationPrompt(hint: String)
    case removeClassifierExample(anchor: String)

    var description: String {
        switch self {
        case .baseline: return "baseline"
        case .addClassifierExample(let i, _): return "addExample(\"\(i.prefix(40))\")"
        case .addClassifierRule(let c): return "addRule(\"\(c.prefix(60))\")"
        case .rewritePresentationPrompt(let h): return "presentationHint(\"\(h.prefix(60))\")"
        case .removeClassifierExample(let a): return "removeExample(\"\(a.prefix(40))\")"
        }
    }
}

// MARK: - Failure Record

struct FailureRecord {
    let input: String
    let history: String?
    let expectedTool: String
    let gotTool: String
    let expectedParamHints: [String: String]
    let gotParams: [String: String]
    let category: EvalCategory
    let failureType: FailureType

    enum FailureType {
        case wrongTool        // routing failure
        case wrongParams      // right tool, bad params
        case badResponse      // right tool+params, response fails rubric
    }
}

// MARK: - Eval Result

struct EvalResult {
    let score: Double                        // weighted 0–1
    let toolRoutingScore: Double             // 35%
    let paramQualityScore: Double            // 35%
    let responseScore: Double                // 30%
    let perCategory: [EvalCategory: Double]
    let failures: [FailureRecord]
    let totalCases: Int

    var summary: String {
        let pct = { (d: Double) in String(format: "%.0f%%", d * 100) }
        var lines = [
            "Score: \(pct(score)) | routing: \(pct(toolRoutingScore)) | params: \(pct(paramQualityScore)) | response: \(pct(responseScore))",
            "Failures: \(failures.count)/\(totalCases)"
        ]
        let sorted = perCategory.sorted { $0.value < $1.value }
        for (cat, s) in sorted {
            lines.append("  \(cat.rawValue): \(pct(s))")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Mock Tool Executor

/// Canned tool responses for eval — same shape as real tool output.
struct MockEvalToolExecutor {
    static func result(tool: String, params: [String: String]) -> String {
        switch tool {
        case "log_food":
            let name = params["name"] ?? params["query"] ?? "food"
            let amount = params["amount"] ?? params["servings"] ?? "1"
            return "Logged \(name) (\(amount) serving). ~250 cal, 12g protein."
        case "food_info":
            let q = (params["query"] ?? "").lowercased()
            if q.contains("calori") { return "Samosa: ~130 cal per piece. 4g protein, 17g carbs, 6g fat." }
            if q.contains("weekly") { return "This week: Mon 1820, Tue 2100, Wed 1650. Avg 1868 cal/day." }
            if q.contains("left") || q.contains("remaining") { return "930 calories remaining today. 1070/2000 cal eaten." }
            if q.contains("protein") { return "Today's protein: 68g of 150g goal (45%)." }
            if q.contains("carb") { return "Carbs today: 120g of 200g goal (60%)." }
            if q.contains("dinner") { return "Dinner logged: dal rice 620 cal." }
            return "Today: 1070/2000 cal. Protein: 68/150g. 930 cal remaining."
        case "weight_info":
            let q = (params["query"] ?? "").lowercased()
            if q.contains("goal") || q.contains("progress") || q.contains("track") {
                return "Current: 78.2kg. Goal: 72kg. Lost 1.8kg in 3 weeks. ~10 weeks to goal. On track ✓"
            }
            return "Weight trend: 78.2kg today, down 0.3kg/week over last month."
        case "sleep_recovery":
            let period = params["period"] ?? ""
            if period.contains("week") { return "This week avg: 7h 10m/night. Best: 7h 45m (Mon). HRV avg: 62ms." }
            return "Last night: 7h 20m. Deep: 1h 45m. REM: 2h 10m. HRV: 68ms. Score: 84/100."
        case "mark_supplement":
            let name = params["name"] ?? "supplement"
            return "Marked \(name) as taken today. ✓"
        case "supplements":
            return "Today: Vitamin D ✓, Creatine ✓, Fish Oil ✗ (not yet). 2/3 taken."
        case "weight_log": fallthrough
        case "log_weight":
            let v = params["value"] ?? "?"; let u = params["unit"] ?? "kg"
            return "Weight logged: \(v) \(u). Previous: 78.5 \(u)."
        case "exercise_info":
            let q = (params["query"] ?? "").lowercased()
            if q.contains("recovery") { return "Muscle recovery: 87% ready. Chest/shoulders well-recovered." }
            return "Recent: Push Day (2d ago), Leg Day (4d ago). Weekly volume on track."
        case "body_comp":
            return "Body comp: 78.2kg, ~18% body fat, 64.1kg lean mass. Losing fat, maintaining muscle."
        case "glucose":
            return "Today: avg 95mg/dL. No spikes >140. Stable after lunch."
        case "biomarkers":
            return "Last labs: cholesterol 185 (normal), HbA1c 5.2% (normal), Vitamin D 32 ng/mL (optimal)."
        case "navigate_to":
            let screen = params["screen"] ?? "?"
            return "Opening \(screen)..."
        case "start_workout":
            return "Starting Push Day. Bench Press, OHP, Incline DB, Lateral Raise loaded."
        case "log_activity":
            let name = params["name"] ?? "activity"; let dur = params["duration"] ?? "30"
            return "Logged \(name) for \(dur) min. ~180 cal burned."
        default:
            return "Done."
        }
    }
}

// MARK: - Optimizer Config

struct OptimizerConfig {
    var budget: Int = 20
    var candidatesPerRound: Int = 3
    var plateauRounds: Int = 3
    var improvementThreshold: Double = 0.01
    var routingWeight: Double = 0.35
    var paramWeight: Double = 0.35
    var responseWeight: Double = 0.30
}

// MARK: - Prompt Optimizer

final class PromptOptimizer {

    let backend: LlamaCppBackend
    let config: OptimizerConfig
    private var triedMutations: Set<String> = []

    init(backend: LlamaCppBackend, config: OptimizerConfig = OptimizerConfig()) {
        self.backend = backend
        self.config = config
    }

    // MARK: - Main Loop

    func runLoop(trainSet: [HardCase], heldOut: [HardCase], baseline: PipelineConfig) async -> (winner: PipelineConfig, report: String) {
        var best = baseline
        let baselineResult = await evaluate(config: baseline, cases: heldOut)
        var bestResult = baselineResult
        var plateauCount = 0
        var roundReports: [String] = []

        print("\n=== DRIFT AUTO-RESEARCH ===")
        print("Budget: \(config.budget) | Train: \(trainSet.count) | Held-out: \(heldOut.count)")
        print("\nBaseline held-out:")
        print(baselineResult.summary)

        let maxRounds = config.budget / config.candidatesPerRound

        for round in 0..<maxRounds {
            let trainResult = await evaluate(config: best, cases: trainSet)
            let candidates = generateMutations(from: best, failures: trainResult.failures)
                .filter { withinTokenBudget($0) && !alreadyTried($0) }
                .prefix(config.candidatesPerRound)

            if candidates.isEmpty {
                roundReports.append("Round \(round + 1): no new candidates — stopping")
                break
            }

            var roundBest: (config: PipelineConfig, result: EvalResult)? = nil
            for candidate in candidates {
                markTried(candidate)
                let result = await evaluate(config: candidate, cases: heldOut)
                if roundBest == nil || result.score > roundBest!.result.score {
                    roundBest = (candidate, result)
                }
            }

            guard let rb = roundBest else { continue }

            let delta = rb.result.score - bestResult.score
            let accepted = delta >= config.improvementThreshold
            let line = "Round \(round + 1): \(rb.config.mutation) → \(String(format: "%.1f%%", rb.result.score * 100)) (\(delta >= 0 ? "+" : "")\(String(format: "%.1f%%", delta * 100))) \(accepted ? "✓ accepted" : "✗ rejected")"
            roundReports.append(line)
            print(line)

            if accepted {
                best = rb.config
                bestResult = rb.result
                plateauCount = 0
            } else {
                plateauCount += 1
                if plateauCount >= config.plateauRounds {
                    roundReports.append("Early termination: \(config.plateauRounds) consecutive rounds < \(String(format: "%.0f%%", config.improvementThreshold * 100)) gain")
                    break
                }
            }
        }

        let finalResult = await evaluate(config: best, cases: trainSet + heldOut)
        let baselineFull = await evaluate(config: baseline, cases: trainSet + heldOut)

        let report = buildReport(
            baselineResult: baselineResult,
            winner: best, winnerResult: bestResult,
            fullResult: finalResult, fullBaseline: baselineFull,
            rounds: roundReports
        )
        print(report)
        return (best, report)
    }

    // MARK: - Evaluation

    func evaluate(config: PipelineConfig, cases: [HardCase]) async -> EvalResult {
        var routingScores: [Double] = []
        var paramScores: [Double] = []
        var responseScores: [Double] = []
        var perCategory: [EvalCategory: [Double]] = [:]
        var failures: [FailureRecord] = []

        for c in cases {
            let userMsg: String
            if let h = c.history, !h.isEmpty {
                userMsg = "Chat:\n\(String(h.prefix(400)))\n\nUser: \(c.input)"
            } else {
                userMsg = c.input
            }

            let raw = await backend.respond(to: userMsg, systemPrompt: config.classifierPrompt) ?? ""
            let (tool, params) = parseToolCall(raw)

            // Tool routing score
            let expectedTool = c.expectedTool
            let routingScore: Double
            if tool == expectedTool {
                routingScore = 1.0
            } else if expectedTool == "chat" && tool == nil {
                routingScore = 1.0
            } else if expectedTool != "chat" && tool == nil {
                routingScore = 0.0
            } else {
                routingScore = 0.0
            }

            // Param quality score
            let paramScore: Double
            if c.expectedParamHints.isEmpty {
                paramScore = 1.0
            } else if routingScore == 0 {
                paramScore = 0.0
            } else {
                let matched = c.expectedParamHints.filter { (key, hint) in
                    let val = (params[key] ?? "").lowercased()
                    return val.contains(hint.lowercased())
                }.count
                paramScore = Double(matched) / Double(c.expectedParamHints.count)
            }

            // Response score — mock tool data + rubric check
            let toolData = tool.map { MockEvalToolExecutor.result(tool: $0, params: params) }
            let response: String
            if let data = toolData, !data.isEmpty {
                let presPrompt = config.presentationPrompt
                    .replacingOccurrences(of: "{timeContext}", with: "afternoon")
                    .replacingOccurrences(of: "{toneHint}", with: "Keep it practical.")
                let presMsg = "Data:\n\(data)\n\nQuestion: \(c.input)"
                response = await backend.respond(to: presMsg, systemPrompt: presPrompt) ?? data
            } else {
                response = raw
            }
            let responseScore = scoreResponse(response, rubric: c.responseRubric)

            // Weighted case score
            let caseScore = routingScore * self.config.routingWeight
                + paramScore * self.config.paramWeight
                + responseScore * self.config.responseWeight

            routingScores.append(routingScore)
            paramScores.append(paramScore)
            responseScores.append(responseScore)
            perCategory[c.category, default: []].append(caseScore)

            // Record failure
            if routingScore < 1 || paramScore < 1 || responseScore < 0.5 {
                let failType: FailureRecord.FailureType = routingScore < 1 ? .wrongTool : paramScore < 1 ? .wrongParams : .badResponse
                failures.append(FailureRecord(
                    input: c.input, history: c.history,
                    expectedTool: c.expectedTool, gotTool: tool ?? "chat",
                    expectedParamHints: c.expectedParamHints, gotParams: params,
                    category: c.category, failureType: failType
                ))
            }
        }

        let avg = { (arr: [Double]) -> Double in arr.isEmpty ? 0 : arr.reduce(0, +) / Double(arr.count) }
        let routingAvg = avg(routingScores)
        let paramAvg = avg(paramScores)
        let responseAvg = avg(responseScores)
        let overallScore = routingAvg * self.config.routingWeight + paramAvg * self.config.paramWeight + responseAvg * self.config.responseWeight
        let catScores = perCategory.mapValues { avg($0) }

        return EvalResult(score: overallScore, toolRoutingScore: routingAvg,
                          paramQualityScore: paramAvg, responseScore: responseAvg,
                          perCategory: catScores, failures: failures, totalCases: cases.count)
    }

    // MARK: - Response Scoring

    private func scoreResponse(_ response: String, rubric: ResponseRubric) -> Double {
        let lower = response.lowercased()

        // Fail if must-not-contain present
        for word in rubric.mustNotContain {
            if lower.contains(word.lowercased()) { return 0.0 }
        }

        // Pass if no must-contain requirements
        if rubric.mustContain.isEmpty { return 1.0 }

        // Score by how many mustContain words appear (OR logic — any match = pass)
        let anyMatch = rubric.mustContain.contains { lower.contains($0.lowercased()) }
        if !anyMatch { return 0.3 }

        // Word count check
        if let maxWords = rubric.maxWords {
            let wordCount = response.split(separator: " ").count
            if wordCount > maxWords { return 0.7 }
        }

        return 1.0
    }

    // MARK: - Mutation Generation

    func generateMutations(from current: PipelineConfig, failures: [FailureRecord]) -> [PipelineConfig] {
        var candidates: [PipelineConfig] = []

        // Priority 1: Add classifier example for each routing failure
        let routingFailures = failures.filter { $0.failureType == .wrongTool }.prefix(3)
        for failure in routingFailures {
            let example = buildExampleString(input: failure.input, tool: failure.expectedTool,
                                              paramHints: failure.expectedParamHints)
            var newPrompt = current.classifierPrompt
            // Insert before last line
            if let lastNewline = newPrompt.lastIndex(of: "\n") {
                newPrompt.insert(contentsOf: "\n\(example)", at: lastNewline)
            } else {
                newPrompt += "\n\(example)"
            }
            candidates.append(PipelineConfig(
                classifierPrompt: newPrompt,
                presentationPrompt: current.presentationPrompt,
                mutation: .addClassifierExample(input: failure.input, output: example)
            ))
        }

        // Priority 2: Add RULES clause when 3+ failures share same wrong-tool pattern
        let routingGroups = Dictionary(grouping: failures.filter { $0.failureType == .wrongTool }) { "\($0.expectedTool)←\($0.gotTool)" }
        for (pattern, group) in routingGroups where group.count >= 3 {
            let parts = pattern.split(separator: "←")
            guard parts.count == 2 else { continue }
            let expected = String(parts[0]), got = String(parts[1])
            let clause = "When user expresses sentiment/future intent about food → \(expected), NOT \(got)."
            var newPrompt = current.classifierPrompt
            if let rulesRange = newPrompt.range(of: "RULES:") {
                let insertPoint = newPrompt.index(rulesRange.upperBound, offsetBy: 0)
                newPrompt.insert(contentsOf: " \(clause)", at: insertPoint)
                candidates.append(PipelineConfig(
                    classifierPrompt: newPrompt,
                    presentationPrompt: current.presentationPrompt,
                    mutation: .addClassifierRule(clause: clause)
                ))
            }
        }

        // Priority 3: Presentation prompt fix when responses fail rubrics
        let responseFailures = failures.filter { $0.failureType == .badResponse }
        if responseFailures.count >= 2 {
            let hasContextSwitch = responseFailures.contains { $0.category == .contextSwitch }
            if hasContextSwitch {
                let hint = "If the topic changes from prior conversation, briefly acknowledge the switch before answering."
                let newPresentation = current.presentationPrompt + "\n\(hint)"
                candidates.append(PipelineConfig(
                    classifierPrompt: current.classifierPrompt,
                    presentationPrompt: newPresentation,
                    mutation: .rewritePresentationPrompt(hint: hint)
                ))
            }
        }

        return candidates
    }

    // MARK: - Source File Application

    /// Apply a winning config back to source files on disk.
    func applyToSourceFiles(_ config: PipelineConfig, projectRoot: URL) throws {
        // Update IntentClassifier.systemPrompt
        let classifierPath = projectRoot.appending(path: "Drift/Services/IntentClassifier.swift")
        try replaceStaticVar(named: "systemPrompt", in: classifierPath, with: config.classifierPrompt)

        // Update AIToolAgent.presentationPrompt
        let agentPath = projectRoot.appending(path: "Drift/Services/AIToolAgent.swift")
        try replaceStaticVar(named: "presentationPrompt", in: agentPath, with: config.presentationPrompt)
    }

    private func replaceStaticVar(named name: String, in fileURL: URL, with newValue: String) throws {
        var source = try String(contentsOf: fileURL, encoding: .utf8)

        // Match: static var <name>: String = """..."""
        let pattern = #"(static var \#(name): String = \"\"\")[\s\S]*?(\"\"\"\s*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let fullRange = Range(match.range, in: source) else {
            throw NSError(domain: "PromptOptimizer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not find 'static var \(name)' in \(fileURL.lastPathComponent)"])
        }

        let escaped = newValue.replacingOccurrences(of: "\\", with: "\\\\")
        let replacement = "static var \(name): String = \"\"\"\n\(escaped)\n\"\"\""
        source.replaceSubrange(fullRange, with: replacement)
        try source.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private func parseToolCall(_ response: String) -> (tool: String?, params: [String: String]) {
        guard let start = response.firstIndex(of: "{"),
              let end = response.lastIndex(of: "}"),
              let data = String(response[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = json["tool"] as? String, !tool.isEmpty else {
            return (nil, [:])
        }
        var params: [String: String] = [:]
        for (k, v) in json where k != "tool" {
            if let s = v as? String { params[k] = s }
            else if let n = v as? Int { params[k] = "\(n)" }
            else if let n = v as? Double { params[k] = "\(n)" }
        }
        return (tool.replacingOccurrences(of: "()", with: ""), params)
    }

    private func buildExampleString(input: String, tool: String, paramHints: [String: String]) -> String {
        var json: [String: String] = ["tool": tool]
        for (k, v) in paramHints { json[k] = v }
        if let data = try? JSONSerialization.data(withJSONObject: json),
           let str = String(data: data, encoding: .utf8) {
            return "\"\(input)\"→\(str)"
        }
        return "\"\(input)\"→{\"tool\":\"\(tool)\"}"
    }

    private func withinTokenBudget(_ config: PipelineConfig) -> Bool {
        let classifierWords = config.classifierPrompt.split(separator: " ").count
        let presentationWords = config.presentationPrompt.split(separator: " ").count
        return classifierWords <= 800 && presentationWords <= 200
    }

    private func mutationKey(_ config: PipelineConfig) -> String {
        config.mutation.description
    }

    private func alreadyTried(_ config: PipelineConfig) -> Bool {
        triedMutations.contains(mutationKey(config))
    }

    private func markTried(_ config: PipelineConfig) {
        triedMutations.insert(mutationKey(config))
    }

    // MARK: - Report

    private func buildReport(
        baselineResult: EvalResult,
        winner: PipelineConfig, winnerResult: EvalResult,
        fullResult: EvalResult, fullBaseline: EvalResult,
        rounds: [String]
    ) -> String {
        let pct = { (d: Double) in String(format: "%.1f%%", d * 100) }
        var lines: [String] = [
            "\n=== DRIFT AUTO-RESEARCH RESULTS ===",
            "Baseline held-out: \(pct(baselineResult.score))",
            "  routing: \(pct(baselineResult.toolRoutingScore)) | params: \(pct(baselineResult.paramQualityScore)) | response: \(pct(baselineResult.responseScore))",
            "",
            "--- Rounds ---"
        ]
        lines += rounds
        lines += [
            "",
            "Winner: \(pct(winnerResult.score)) held-out (+\(pct(winnerResult.score - baselineResult.score)) vs baseline)",
            "Full set score: \(pct(fullResult.score)) (baseline \(pct(fullBaseline.score)))",
            "Mutation: \(winner.mutation)",
            ""
        ]
        if case .baseline = winner.mutation {
            lines.append("No improvement found — baseline is optimal for this eval set.")
        }
        lines.append("\nAUTO-APPLY: Run testAutoResearch to apply and push if regression-free.")
        return lines.joined(separator: "\n")
    }
}
