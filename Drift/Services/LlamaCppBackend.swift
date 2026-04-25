import Foundation
import DriftCore
import llama

/// llama.cpp backend using raw C API — bypasses LLM.swift wrapper which has Metal issues on device.
final class LlamaCppBackend: AIBackend, @unchecked Sendable {
    private var model: OpaquePointer?                       // llama_model *
    private var context: OpaquePointer?                     // llama_context *
    private let modelPath: URL
    private var isGemma: Bool = false  // Gemma uses different chat template
    private let threadOverride: Int?  // nil = auto, set lower for parallel eval

    var isLoaded: Bool { model != nil && context != nil }
    var supportsVision: Bool { false }

    init(modelPath: URL, threads: Int? = nil) {
        self.modelPath = modelPath
        self.threadOverride = threads
    }

    func loadSync() throws {
        try _load()
    }

    func load() async throws {
        try _load()
    }

    enum LoadError: LocalizedError {
        case modelLoadFailed
        case contextCreateFailed
        var errorDescription: String? {
            switch self {
            case .modelLoadFailed: "Model file could not be loaded."
            case .contextCreateFailed: "Could not create inference context."
            }
        }
    }

    // MARK: - Load

    private func _load() throws {
        guard model == nil else { return }

        let cPath = modelPath.path.cString(using: .utf8)!

        // GPU acceleration: xcframework built from source with Xcode 17 Metal SDK
        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0    // no Metal on simulator
        #else
        modelParams.n_gpu_layers = 999  // offload all layers to A19 Pro GPU
        #endif
        guard let m = llama_model_load_from_file(cPath, modelParams) else {
            throw LoadError.modelLoadFailed
        }
        model = m

        // Create context — CPU optimized
        var ctxParams = llama_context_default_params()
        let trainCtx = llama_model_n_ctx_train(m)
        ctxParams.n_ctx = min(4096, UInt32(trainCtx))
        ctxParams.n_batch = min(4096, UInt32(trainCtx))

        // Dynamic thread count based on device cores (or explicit override for parallel eval)
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        if let t = threadOverride {
            ctxParams.n_threads = Int32(t)
            ctxParams.n_threads_batch = Int32(t)
        } else {
            ctxParams.n_threads = Int32(max(2, min(coreCount - 2, 6)))       // leave 2 for UI
            ctxParams.n_threads_batch = Int32(max(2, min(coreCount, 8)))     // use all for prompt eval
        }

        // KV cache at full precision for best quality
        // (Q8_0 was faster but degraded response quality)

        ctxParams.offload_kqv = true
        ctxParams.op_offload = true

        // Try GPU context first, fall back to pure CPU if Metal fails
        var c = llama_init_from_model(m, ctxParams)
        if c == nil {
            Log.app.info("AI: GPU context failed, reloading model CPU-only")
            llama_model_free(m)

            // Reload model with CPU-only device to avoid Metal entirely
            var cpuDev: ggml_backend_dev_t?
            for i in 0..<ggml_backend_reg_count() {
                let reg = ggml_backend_reg_get(i)
                let regName = String(cString: ggml_backend_reg_name(reg))
                if regName == "CPU" { cpuDev = ggml_backend_reg_dev_get(reg, 0); break }
            }
            var cpuParams = llama_model_default_params()
            cpuParams.n_gpu_layers = 0
            var devList: [ggml_backend_dev_t?] = []
            if let cpuDev {
                devList = [cpuDev, nil]
                cpuParams.devices = UnsafeMutablePointer(mutating: devList.withUnsafeBufferPointer { $0.baseAddress })
            }
            guard let cpuModel = withExtendedLifetime(devList, { llama_model_load_from_file(cPath, cpuParams) }) else {
                throw LoadError.modelLoadFailed
            }
            model = cpuModel

            ctxParams.offload_kqv = false
            ctxParams.op_offload = false
            c = llama_init_from_model(cpuModel, ctxParams)
        }
        guard let c else {
            llama_model_free(m)
            model = nil
            throw LoadError.contextCreateFailed
        }
        context = c

        // Detect model family from filename for chat template
        self.isGemma = modelPath.lastPathComponent.lowercased().contains("gemma")
        Log.app.info("AI: model loaded via raw C API (ctx=\(ctxParams.n_ctx), gemma=\(self.isGemma))")
    }

    // MARK: - Sampler

    /// Build a sampler chain for one inference call. Caller owns it and must call llama_sampler_free().
    /// temperature=0 → greedy (deterministic) — use for intent classification.
    /// temperature>0 → stochastic (top-p) — use for presentation / conversational responses.
    private func makeSampler(temperature: Float) -> UnsafeMutablePointer<llama_sampler> {
        let s = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        if temperature <= 0 {
            llama_sampler_chain_add(s, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(s, llama_sampler_init_temp(temperature))
            llama_sampler_chain_add(s, llama_sampler_init_top_p(0.9, 1))
            llama_sampler_chain_add(s, llama_sampler_init_dist(UInt32.random(in: .min ... .max)))
        }
        return s
    }

    // MARK: - Inference (AIBackend protocol)

    /// Protocol conformance: greedy (temp=0) — deterministic, ideal for intent classification.
    func respond(to prompt: String, systemPrompt: String) async -> String {
        await _respondStreaming(to: prompt, systemPrompt: systemPrompt, temperature: 0.0, onToken: { _ in })
    }

    /// Protocol conformance: stochastic (temp=0.4) — natural presentation responses.
    func respondStreaming(to prompt: String, systemPrompt: String, onToken: @escaping @Sendable (String) -> Void) async -> String {
        await _respondStreaming(to: prompt, systemPrompt: systemPrompt, temperature: 0.4, onToken: onToken)
    }

    // MARK: - Inference (extended API)

    /// Explicit temperature control. Use temperature=0 for greedy/deterministic output.
    func respond(to prompt: String, systemPrompt: String, temperature: Float) async -> String {
        await _respondStreaming(to: prompt, systemPrompt: systemPrompt, temperature: temperature, onToken: { _ in })
    }

    /// Explicit temperature control with streaming.
    func respondStreaming(to prompt: String, systemPrompt: String, temperature: Float, onToken: @escaping @Sendable (String) -> Void) async -> String {
        await _respondStreaming(to: prompt, systemPrompt: systemPrompt, temperature: temperature, onToken: onToken)
    }

    // MARK: - Core Inference

    private func _respondStreaming(to prompt: String, systemPrompt: String, temperature: Float, onToken: @escaping @Sendable (String) -> Void) async -> String {
        guard let model, let context else { return "" }

        // Build prompt using model-appropriate chat template
        let fullPrompt: String
        if isGemma {
            fullPrompt = "<start_of_turn>user\n\(systemPrompt)\n\n\(prompt)<end_of_turn>\n<start_of_turn>model\n"
        } else {
            // ChatML for Qwen, SmolLM, etc.
            fullPrompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n<|im_start|>user\n\(prompt)<|im_end|>\n<|im_start|>assistant\n"
        }

        // Tokenize and enforce context limit (leave room for generation)
        var tokens = tokenize(text: fullPrompt, addBos: true)
        guard !tokens.isEmpty else { return "" }

        let maxPromptTokens = 4096 - 512 - 16 // context - generation - safety margin
        if tokens.count > maxPromptTokens {
            Log.app.info("AI: prompt truncated \(tokens.count) → \(maxPromptTokens) tokens")
            tokens = Array(tokens.prefix(maxPromptTokens))
        }

        // Clear KV cache
        let mem = llama_get_memory(context)
        if let mem { llama_memory_clear(mem, true) }

        // Process prompt
        let promptBatch = llama_batch_get_one(&tokens, Int32(tokens.count))
        if llama_decode(context, promptBatch) != 0 { return "" }

        // Build per-call sampler — freed when this call returns
        let callSampler = makeSampler(temperature: temperature)
        defer { llama_sampler_free(callSampler) }

        // Generate token by token
        var outputBuf: [CChar] = []
        let maxNewTokens = 512
        let vocab = llama_model_get_vocab(model)
        let eosToken = llama_vocab_eos(vocab)
        let eotToken = llama_vocab_eot(vocab)

        for _ in 0..<maxNewTokens {
            let newToken = llama_sampler_sample(callSampler, context, -1)
            if newToken == eosToken || newToken == eotToken { break }

            // Token to text
            var buf = [CChar](repeating: 0, count: 256)
            let len = llama_token_to_piece(vocab, newToken, &buf, 256, 0, false)
            if len > 0 {
                let piece = buf.prefix(Int(len))
                outputBuf.append(contentsOf: piece)

                // Stream piece to caller, filtering chat template tokens
                let tokenStr = String(cString: Array(piece) + [0])
                let stopTokens = ["<|im_end|>", "<|im_start|>", "<end_of_turn>", "<start_of_turn>"]
                if !stopTokens.contains(where: { tokenStr.contains($0) }) {
                    onToken(tokenStr)
                }
            }

            // Early JSON termination: stop as soon as we have complete JSON
            if let first = outputBuf.first, first == 0x7B { // starts with '{'
                let opens = outputBuf.filter { $0 == 0x7B }.count
                let closes = outputBuf.filter { $0 == 0x7D }.count
                if closes > 0 && opens == closes { break }
            }

            // Check stop sequence in tail (not entire buffer — avoids O(n) scan)
            let bufLen = outputBuf.count
            if bufLen >= 10 {
                let tailStart = max(0, bufLen - 32)
                let tail = Array(outputBuf[tailStart...]) + [0]
                let tailStr = String(cString: tail)
                if tailStr.contains("<|im_end|>") || tailStr.contains("<end_of_turn>") { break }
            }

            // Feed token back
            var tokenArr = [newToken]
            let nextBatch = llama_batch_get_one(&tokenArr, 1)
            if llama_decode(context, nextBatch) != 0 { break }
        }

        guard !outputBuf.isEmpty else { return "" }
        var result = String(cString: outputBuf + [0])
        // Strip any trailing chat template tokens
        for stop in ["<|im_end|>", "<|im_start|>", "<end_of_turn>", "<start_of_turn>"] {
            if let range = result.range(of: stop) {
                result = String(result[..<range.lowerBound])
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tokenize

    private func tokenize(text: String, addBos: Bool) -> [llama_token] {
        guard let model else { return [] }
        let vocab = llama_model_get_vocab(model)
        let maxTokens = Int32(text.utf8.count) + 16
        var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
        let count = llama_tokenize(vocab, text, Int32(text.utf8.count), &tokens, maxTokens, addBos, true)
        guard count > 0 else { return [] }
        return Array(tokens.prefix(Int(count)))
    }

    // MARK: - Cleanup

    func unload() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
    }

    deinit {
        unload()
    }
}
