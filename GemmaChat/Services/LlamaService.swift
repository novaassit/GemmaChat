import Foundation
import llama

/// Wraps llama.cpp C API for Gemma 4 E2B inference on-device.
@MainActor
final class LlamaService: ObservableObject {

    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var loadError: String?
    @Published var modelLoaded = false

    private var model: OpaquePointer?   // llama_model *
    private var context: OpaquePointer? // llama_context *
    private var vocab: OpaquePointer?   // llama_vocab *

    private let maxTokens = 512
    private let contextSize: UInt32 = 4096

    // MARK: - Model Loading

    func loadModel(at path: String) async {
        isLoading = true
        loadError = nil

        // Run heavy work off main
        let result: (OpaquePointer?, OpaquePointer?, OpaquePointer?, String?) = await Task.detached(priority: .userInitiated) {
            // Init backend once
            llama_backend_init()

            // Model params (use Metal GPU on iOS)
            var modelParams = llama_model_default_params()
            modelParams.n_gpu_layers = 99 // offload everything to Metal

            guard let model = llama_model_load_from_file(path, modelParams) else {
                return (nil, nil, nil, "모델 파일을 로드할 수 없습니다: \(path)")
            }

            let vocab = llama_model_get_vocab(model)

            // Context params
            var ctxParams = llama_context_default_params()
            ctxParams.n_ctx = self.contextSize
            ctxParams.n_batch = 512
            ctxParams.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))
            ctxParams.n_threads_batch = ctxParams.n_threads

            guard let ctx = llama_init_from_model(model, ctxParams) else {
                llama_model_free(model)
                return (nil, nil, nil, "컨텍스트를 초기화할 수 없습니다")
            }

            return (model, ctx, vocab, nil)
        }.value

        self.model = result.0
        self.context = result.1
        self.vocab = result.2
        self.loadError = result.3
        self.modelLoaded = result.0 != nil
        self.isLoading = false
    }

    // MARK: - Chat Completion (streaming via AsyncStream)

    func generate(messages: [ChatMessage]) -> AsyncStream<String> {
        AsyncStream { continuation in
            guard let model = self.model,
                  let context = self.context,
                  let vocab = self.vocab else {
                continuation.finish()
                return
            }

            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { continuation.finish(); return }

                await MainActor.run { self.isGenerating = true }
                defer { Task { @MainActor in self.isGenerating = false } }

                // Format prompt in Gemma chat template
                let prompt = self.formatPrompt(messages: messages)

                // Tokenize
                let promptCStr = prompt.cString(using: .utf8)!
                let maxTokenCount = Int32(prompt.count + 256)
                var tokens = [llama_token](repeating: 0, count: Int(maxTokenCount))
                let nTokens = llama_tokenize(vocab, promptCStr, Int32(promptCStr.count - 1), &tokens, maxTokenCount, true, true)

                guard nTokens > 0 else {
                    continuation.finish()
                    return
                }

                tokens = Array(tokens.prefix(Int(nTokens)))

                // Clear memory (KV cache)
                llama_memory_clear(llama_get_memory(context), true)

                // Create batch and process prompt
                var batch = llama_batch_init(Int32(tokens.count), 0, 1)

                for (i, token) in tokens.enumerated() {
                    batch.n_tokens = Int32(i + 1)
                    batch.token[i] = token
                    batch.pos[i] = Int32(i)
                    batch.n_seq_id[i] = 1
                    batch.seq_id[i]![0] = 0
                    batch.logits[i] = (i == tokens.count - 1) ? 1 : 0 // only last token needs logits
                }

                if llama_decode(context, batch) != 0 {
                    llama_batch_free(batch)
                    continuation.finish()
                    return
                }

                // Generate tokens one by one
                var nCur = Int(nTokens)
                let eosToken = llama_vocab_eos(vocab)
                let eotToken = llama_vocab_eot(vocab)

                // Greedy sampler
                let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())!
                llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.7))
                llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
                llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

                for _ in 0..<self.maxTokens {
                    let newTokenId = llama_sampler_sample(sampler, context, Int32(batch.n_tokens - 1))

                    // Check for end of generation
                    if newTokenId == eosToken || newTokenId == eotToken {
                        break
                    }

                    // Decode token to text
                    var buf = [CChar](repeating: 0, count: 256)
                    let len = llama_token_to_piece(vocab, newTokenId, &buf, Int32(buf.count), 0, true)
                    if len > 0 {
                        let piece = String(cString: buf)
                        continuation.yield(piece)
                    }

                    // Prepare next batch (manual clear)
                    batch.n_tokens = 0
                    batch.n_tokens = 1
                    batch.token[0] = newTokenId
                    batch.pos[0] = Int32(nCur)
                    batch.n_seq_id[0] = 1
                    batch.seq_id[0]![0] = 0
                    batch.logits[0] = 1

                    nCur += 1

                    if llama_decode(context, batch) != 0 {
                        break
                    }
                }

                llama_sampler_free(sampler)
                llama_batch_free(batch)
                continuation.finish()
            }
        }
    }

    // MARK: - Gemma Chat Template

    private nonisolated func formatPrompt(messages: [ChatMessage]) -> String {
        var prompt = ""
        for msg in messages {
            switch msg.role {
            case .user:
                prompt += "<start_of_turn>user\n\(msg.content)<end_of_turn>\n"
            case .assistant:
                prompt += "<start_of_turn>model\n\(msg.content)<end_of_turn>\n"
            case .system:
                prompt += "<start_of_turn>system\n\(msg.content)<end_of_turn>\n"
            }
        }
        // Signal model to start generating
        prompt += "<start_of_turn>model\n"
        return prompt
    }

    // MARK: - Cleanup

    func unload() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        self.context = nil
        self.model = nil
        self.vocab = nil
        self.modelLoaded = false
        llama_backend_free()
    }

    deinit {
        // Note: deinit can't call unload() directly on MainActor
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }
}
