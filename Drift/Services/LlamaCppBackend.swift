import Foundation
import llama

/// llama.cpp backend using raw C API — bypasses LLM.swift wrapper which has Metal issues on device.
final class LlamaCppBackend: AIBackend, @unchecked Sendable {
    private var model: OpaquePointer?                       // llama_model *
    private var context: OpaquePointer?                     // llama_context *
    private var smpl: UnsafeMutablePointer<llama_sampler>?  // llama_sampler *
    private let modelPath: URL

    var isLoaded: Bool { model != nil && context != nil }
    var supportsVision: Bool { false }

    init(modelPath: URL) {
        self.modelPath = modelPath
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

        // Force CPU-only: find the CPU device and pass it explicitly.
        // This prevents llama.cpp from initializing Metal (which crashes on A19 Pro
        // due to incompatible Metal shader compilation with the prebuilt xcframework).
        var cpuDev: ggml_backend_dev_t?
        for i in 0..<ggml_backend_reg_count() {
            let reg = ggml_backend_reg_get(i)
            let name = String(cString: ggml_backend_reg_name(reg))
            if name == "CPU" {
                cpuDev = ggml_backend_reg_dev_get(reg, 0)
                break
            }
        }

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 0
        var deviceList: [ggml_backend_dev_t?] = []
        if let cpuDev {
            deviceList = [cpuDev, nil] // NULL-terminated
            modelParams.devices = UnsafeMutablePointer(mutating: deviceList.withUnsafeBufferPointer { $0.baseAddress })
        }
        guard let m = withExtendedLifetime(deviceList, { llama_model_load_from_file(cPath, modelParams) }) else {
            throw LoadError.modelLoadFailed
        }
        model = m

        // Create context — also CPU only
        var ctxParams = llama_context_default_params()
        let trainCtx = llama_model_n_ctx_train(m)
        ctxParams.n_ctx = min(2048, UInt32(trainCtx))
        ctxParams.n_batch = min(2048, UInt32(trainCtx))
        ctxParams.offload_kqv = false
        ctxParams.op_offload = false
        guard let c = llama_init_from_model(m, ctxParams) else {
            llama_model_free(m)
            model = nil
            throw LoadError.contextCreateFailed
        }
        context = c

        // Create sampler chain
        let s = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        llama_sampler_chain_add(s, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(s, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(s, llama_sampler_init_dist(UInt32.random(in: .min ... .max)))
        smpl = s

        Log.app.info("AI: model loaded via raw C API (ctx=\(ctxParams.n_ctx))")
    }

    // MARK: - Inference

    func respond(to prompt: String, systemPrompt: String) async -> String {
        guard let model, let context, let smpl else { return "" }

        // Build ChatML prompt
        let fullPrompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n<|im_start|>user\n\(prompt)<|im_end|>\n<|im_start|>assistant\n"

        // Tokenize
        var tokens = tokenize(text: fullPrompt, addBos: true)
        guard !tokens.isEmpty else { return "" }

        // Clear memory (KV cache)
        let mem = llama_get_memory(context)
        if let mem { llama_memory_clear(mem, true) }

        // Process prompt
        let promptBatch = llama_batch_get_one(&tokens, Int32(tokens.count))
        if llama_decode(context, promptBatch) != 0 { return "" }

        // Generate
        var outputBuf: [CChar] = []
        let maxNewTokens = 256
        let vocab = llama_model_get_vocab(model)
        let eosToken = llama_vocab_eos(vocab)
        let eotToken = llama_vocab_eot(vocab)

        for _ in 0..<maxNewTokens {
            let newToken = llama_sampler_sample(smpl, context, -1)
            if newToken == eosToken || newToken == eotToken { break }

            // Token to text
            var buf = [CChar](repeating: 0, count: 256)
            let len = llama_token_to_piece(vocab, newToken, &buf, 256, 0, false)
            if len > 0 {
                outputBuf.append(contentsOf: buf.prefix(Int(len)))
            }

            // Check stop sequence
            let partial = String(cString: outputBuf + [0])
            if partial.contains("<|im_end|>") { break }

            // Feed token back
            var tokenArr = [newToken]
            let nextBatch = llama_batch_get_one(&tokenArr, 1)
            if llama_decode(context, nextBatch) != 0 { break }
        }

        llama_sampler_reset(smpl)

        guard !outputBuf.isEmpty else { return "" }
        var result = String(cString: outputBuf + [0])
        if let range = result.range(of: "<|im_end|>") {
            result = String(result[..<range.lowerBound])
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
        if let smpl { llama_sampler_free(smpl) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        smpl = nil
        context = nil
        model = nil
    }

    deinit {
        unload()
    }
}
