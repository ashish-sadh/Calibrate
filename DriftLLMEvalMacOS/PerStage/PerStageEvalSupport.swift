import XCTest
import DriftCore
import Foundation

// MARK: - Shared model loader + prompt for per-stage LLM evals

/// Shared Gemma backend, loaded once and reused across all per-stage LLM evals.
/// nonisolated(unsafe) mirrors the pattern used in IntentRoutingEval.
nonisolated(unsafe) var perStageGemmaBackend: LlamaCppBackend?

enum PerStageEvalSupport {

    static let modelPath = URL.homeDirectory
        .appending(path: "drift-state/models/gemma-4-e2b-q4_k_m.gguf")

    /// Load the Gemma model into perStageGemmaBackend. Call from class setUp().
    /// Calls fatalError when the model file is missing so the failure is visible.
    static func loadModel() {
        guard LLMEvalGate.enabled else { return }  // Tier-3 gate: default run must not load the model
        guard perStageGemmaBackend == nil else { return }
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            fatalError("❌ Gemma model not found at \(modelPath.path)\nRun: bash scripts/download-models.sh")
        }
        let b = LlamaCppBackend(modelPath: modelPath, threads: 6)
        try? b.loadSync()
        guard b.isLoaded else {
            fatalError("❌ Gemma model failed to load — check model file integrity")
        }
        perStageGemmaBackend = b
        print("✅ [PerStageEval] Gemma loaded")
    }

    // MARK: - Shared system prompt (live reference, never duplicated)
    //
    // We test the same prompt the production app uses. Previously this was a
    // byte-for-byte copy of IntentClassifier.systemPrompt — but the copy
    // silently drifted, so for ~weeks the macOS eval was scoring against a
    // snapshot prompt while production shipped a different one. Single
    // source of truth: route via DriftCore. The eval target tests the
    // Gemma path (large model), so we want the intelligence prompt.
    static var systemPrompt: String { IntentClassifier.intelligencePrompt }

    // MARK: - Shared helpers

    /// Delegates to the production parser so the eval measures what users get —
    /// including its hallucinated-tool-name aliasing (weight_history → weight_info).
    static func extractTool(_ response: String) -> String? {
        IntentClassifier.parseResponse(response)?.tool
    }

    static func classify(_ message: String, history: String = "") async -> String? {
        guard let backend = perStageGemmaBackend else { return nil }
        let userMsg = history.isEmpty ? message : "Chat:\n\(String(history.prefix(400)))\n\nUser: \(message)"
        return await backend.respond(to: userMsg, systemPrompt: systemPrompt)
    }
}

// MARK: - XCTestCase helper

extension XCTestCase {
    func assertRoutesSingleStage(
        _ query: String,
        to expectedTool: String,
        history: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> Bool {
        guard let response = await PerStageEvalSupport.classify(query, history: history) else {
            XCTFail("No response for '\(query)'", file: file, line: line)
            return false
        }
        let tool = PerStageEvalSupport.extractTool(response)
        let ok = tool == expectedTool
        if !ok {
            print("❌ [\(String(describing: type(of: self)))] '\(query)' → '\(tool ?? "text")' (expected '\(expectedTool)')")
        }
        return ok
    }
}
