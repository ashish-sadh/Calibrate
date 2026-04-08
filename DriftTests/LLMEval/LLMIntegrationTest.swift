import XCTest
@testable import Drift

/// Thread-safe counter for streaming tests.
private final class Counter: @unchecked Sendable {
    private var _value = 0
    var value: Int { _value }
    func increment() { _value += 1 }
}

/// Integration test: verifies LLM.swift can load a GGUF model and produce output.
/// Uses the smallest available model (SmolLM2-360M) for speed.
final class LLMIntegrationTest: XCTestCase {

    nonisolated(unsafe) static var backend: LlamaCppBackend?
    nonisolated(unsafe) static var modelName: String = ""

    override class func setUp() {
        super.setUp()
        // Try models from smallest to largest — use first available
        let candidates: [(String, String)] = [
            ("/tmp/smollm2-360m-instruct-q8_0.gguf", "SmolLM2-360M"),
            ("/tmp/qwen2.5-0.5b-instruct-q4_k_m.gguf", "Qwen2.5-0.5B"),
            ("/tmp/qwen2.5-1.5b-instruct-q4_k_m.gguf", "Qwen2.5-1.5B"),
        ]
        for (path, name) in candidates {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let b = LlamaCppBackend(modelPath: URL(fileURLWithPath: path))
            try? b.loadSync()
            if b.isLoaded {
                backend = b
                modelName = name
                print("✅ LLM Integration: loaded \(name)")
                return
            }
        }
        print("⚠️ No model found at /tmp/ — skipping LLM integration tests")
    }

    func testModelLoads() throws {
        guard let b = Self.backend else { throw XCTSkip("No model available") }
        XCTAssertTrue(b.isLoaded, "Backend should report isLoaded=true")
    }

    func testModelInference() async throws {
        guard let b = Self.backend else { throw XCTSkip("No model available") }
        let response = await b.respond(to: "Say hello.", systemPrompt: "Reply in one word.")
        print("\(Self.modelName) response: '\(response)'")
        XCTAssertFalse(response.isEmpty, "Model should produce a non-empty response")
    }

    func testStreamingGeneratesTokens() async throws {
        guard let b = Self.backend else { throw XCTSkip("No model available") }
        let counter = Counter()
        let response = await b.respondStreaming(to: "Say hello.", systemPrompt: "Reply briefly.") { _ in
            counter.increment()
        }
        XCTAssertFalse(response.isEmpty, "Should produce output")
        XCTAssertGreaterThan(counter.value, 0, "Should stream at least 1 token")
        print("Streaming: \(counter.value) tokens, response: '\(response)'")
    }

    func testLLMWithContext() async throws {
        guard let b = Self.backend else { throw XCTSkip("No model available") }
        let context = "Eaten: 1200/1800cal | 600 left | 80P 120C 40F\nGoal: losing to 155lbs | 60% done"
        let prompt = "Context about the user:\n\(context)\n\nUser: How am I doing today?"
        let response = await b.respond(to: prompt, systemPrompt: "Health assistant. Use ONLY context data. 2-3 sentences.")
        print("Context test: '\(response)'")
        XCTAssertFalse(response.isEmpty)
        let isRelevant = response.lowercased().contains("calor") || response.lowercased().contains("goal")
            || response.lowercased().contains("target") || response.lowercased().contains("track")
            || response.contains("1200") || response.contains("1800") || response.contains("600")
        XCTAssertTrue(isRelevant, "Model should produce health-relevant response")
    }
}
