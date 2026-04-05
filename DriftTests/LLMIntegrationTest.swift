import XCTest
@testable import Drift

/// Integration test: verifies LLM.swift can load a GGUF model and produce output.
final class LLMIntegrationTest: XCTestCase {

    /// Check if the LLM backend can load a model file.
    func testModelLoads() throws {
        let modelPath = URL(fileURLWithPath: "/tmp/qwen2.5-0.5b-instruct-q4_k_m.gguf")
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw XCTSkip("Model not found at /tmp/ — download first")
        }

        let backend = LlamaCppBackend(modelPath: modelPath)
        try backend.loadSync()
        XCTAssertTrue(backend.isLoaded, "Backend should report isLoaded=true after loadSync")
    }

    /// Full end-to-end: load 0.5B + run inference.
    func testModelInference() async throws {
        let modelPath = URL(fileURLWithPath: "/tmp/qwen2.5-0.5b-instruct-q4_k_m.gguf")
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw XCTSkip("Model not found at /tmp/ — download first")
        }

        let backend = LlamaCppBackend(modelPath: modelPath)
        try backend.loadSync()
        XCTAssertTrue(backend.isLoaded)

        let response = await backend.respond(to: "Say hello.", systemPrompt: "Reply in one word.")
        print("LLM 0.5B response: '\(response)'")
        XCTAssertFalse(response.isEmpty, "Model should produce a non-empty response")
    }

    /// Test SmolLM2-1.7B Q4_K_M.
    func testSmolLM2_1_7B() async throws {
        let modelPath = URL(fileURLWithPath: "/tmp/smollm2-1.7b-instruct-q4_k_m.gguf")
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw XCTSkip("SmolLM2-1.7B not found at /tmp/")
        }

        let backend = LlamaCppBackend(modelPath: modelPath)
        try backend.loadSync()
        XCTAssertTrue(backend.isLoaded)

        let response = await backend.respond(to: "I ate 1200 calories today, target is 1800. How am I doing?", systemPrompt: "You are a brief health assistant. Answer in 2-3 sentences.")
        print("SmolLM2-1.7B response: '\(response)'")
        XCTAssertFalse(response.isEmpty)
    }

    /// Test Qwen2.5-0.5B with raw C API (was failing via LLM.swift wrapper).
    func testQwen05B() async throws {
        let modelPath = URL(fileURLWithPath: "/tmp/qwen2.5-0.5b-instruct-q4_k_m.gguf")
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw XCTSkip("Qwen2.5-0.5B not found at /tmp/")
        }

        let backend = LlamaCppBackend(modelPath: modelPath)
        try backend.loadSync()
        XCTAssertTrue(backend.isLoaded)

        let response = await backend.respond(to: "What is 2+2?", systemPrompt: "Answer briefly.")
        print("Qwen2.5-0.5B response: '\(response)'")
        XCTAssertFalse(response.isEmpty)
    }

    /// Test Qwen2.5-1.5B with raw C API.
    func testQwen15B() async throws {
        let modelPath = URL(fileURLWithPath: "/tmp/qwen2.5-1.5b-instruct-q4_k_m.gguf")
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw XCTSkip("Qwen2.5-1.5B not found at /tmp/")
        }

        let backend = LlamaCppBackend(modelPath: modelPath)
        try backend.loadSync()
        XCTAssertTrue(backend.isLoaded)

        let response = await backend.respond(to: "I ate 1200 calories today, target is 1800. How am I doing?", systemPrompt: "You are a brief health assistant. Answer in 2-3 sentences.")
        print("Qwen2.5-1.5B response: '\(response)'")
        XCTAssertFalse(response.isEmpty)
    }
}
