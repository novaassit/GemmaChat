import Foundation
import llama

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

        let result: (OpaquePointer?, OpaquePointer?, OpaquePointer?, String?) = await Task.detached(priority: .userInitiated) {
            llama_backend_init()

            var modelParams = llama_model_default_params()
            modelParams.n_gpu_layers = 99

            guard let model = llama_model_load_from_file(path, modelParams) else {
                return (nil, nil, nil, "모델 파일을 로드할 수 없습니다: \(path)")
            }

            let vocab = llama_model_get_vocab(model)

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

    func generate(systemPrompt: String? = nil, messages: [ChatMessage]) -> AsyncStream<String> {
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

                // Build full prompt as a single string (safe, no tokenization split issues).
                var prompt = ""
                if let sys = systemPrompt {
                    prompt += "<start_of_turn>system\n\(sys)<end_of_turn>\n"
                }
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
                prompt += "<start_of_turn>model\n"

                // Tokenize entire prompt as one piece.
                let promptCStr = prompt.cString(using: .utf8)!
                let maxTokenCount = Int32(self.contextSize)
                var tokens = [llama_token](repeating: 0, count: Int(maxTokenCount))
                let nTokens = llama_tokenize(vocab, promptCStr, Int32(promptCStr.count - 1), &tokens, maxTokenCount, true, true)

                guard nTokens > 0 else {
                    continuation.finish()
                    return
                }

                tokens = Array(tokens.prefix(Int(nTokens)))

                // Clear KV cache fully each turn.
                llama_memory_clear(llama_get_memory(context), true)

                let chunkCapacity = 512
                var batch = llama_batch_init(Int32(chunkCapacity), 0, 1)

                var promptPos = 0
                let tokensToProcess = tokens
                var promptDecodeFailed = false

                while promptPos < tokensToProcess.count {
                    let thisChunk = min(chunkCapacity, tokensToProcess.count - promptPos)
                    batch.n_tokens = Int32(thisChunk)
                    for i in 0..<thisChunk {
                        let globalIdx = promptPos + i
                        batch.token[i] = tokensToProcess[promptPos + i]
                        batch.pos[i] = Int32(globalIdx)
                        batch.n_seq_id[i] = 1
                        batch.seq_id[i]![0] = 0
                        batch.logits[i] = (globalIdx == tokens.count - 1) ? 1 : 0
                    }

                    if llama_decode(context, batch) != 0 {
                        promptDecodeFailed = true
                        break
                    }

                    promptPos += thisChunk
                }

                if promptDecodeFailed {
                    llama_batch_free(batch)
                    continuation.finish()
                    return
                }

                // --- Token generation loop ---
                var nCur = tokens.count

                var stopTokens = Set<llama_token>()
                let eosToken = llama_vocab_eos(vocab)
                if eosToken >= 0 { stopTokens.insert(eosToken) }
                let eotToken = llama_vocab_eot(vocab)
                if eotToken >= 0 { stopTokens.insert(eotToken) }

                let endOfTurnStr = "<end_of_turn>"
                var endOfTurnTokens = [llama_token](repeating: 0, count: 8)
                let endOfTurnCount = llama_tokenize(vocab, endOfTurnStr, Int32(endOfTurnStr.utf8.count), &endOfTurnTokens, 8, false, true)
                if endOfTurnCount == 1 {
                    stopTokens.insert(endOfTurnTokens[0])
                }

                let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())!
                llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.7))
                llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
                llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

                let stopSequences = ["<end_of_turn>", "<start_of_turn>"]
                var pendingBuffer = ""
                var textStopped = false

                for _ in 0..<self.maxTokens {
                    let newTokenId = llama_sampler_sample(sampler, context, Int32(batch.n_tokens - 1))

                    if stopTokens.contains(newTokenId) || llama_vocab_is_eog(vocab, newTokenId) {
                        break
                    }

                    var buf = [CChar](repeating: 0, count: 256)
                    let len = llama_token_to_piece(vocab, newTokenId, &buf, Int32(buf.count), 0, false)
                    if len > 0 {
                        let piece = String(cString: buf)
                        pendingBuffer += piece

                        var foundFullStop = false
                        for stop in stopSequences {
                            if let range = pendingBuffer.range(of: stop) {
                                let safeText = String(pendingBuffer[..<range.lowerBound])
                                if !safeText.isEmpty {
                                    continuation.yield(safeText)
                                }
                                foundFullStop = true
                                break
                            }
                        }
                        if foundFullStop {
                            textStopped = true
                            break
                        }

                        var holdback = 0
                        for stop in stopSequences {
                            let maxCheck = min(stop.count - 1, pendingBuffer.count)
                            if maxCheck >= 1 {
                                for i in 1...maxCheck {
                                    let partial = String(stop.prefix(i))
                                    if pendingBuffer.hasSuffix(partial) {
                                        holdback = max(holdback, i)
                                    }
                                }
                            }
                        }

                        if pendingBuffer.count > holdback {
                            let yieldEnd = pendingBuffer.index(pendingBuffer.endIndex, offsetBy: -holdback)
                            let yieldText = String(pendingBuffer[..<yieldEnd])
                            continuation.yield(yieldText)
                            pendingBuffer = String(pendingBuffer[yieldEnd...])
                        }
                    }

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

                if !textStopped && !pendingBuffer.isEmpty {
                    continuation.yield(pendingBuffer)
                }

                llama_sampler_free(sampler)
                llama_batch_free(batch)
                continuation.finish()
            }
        }
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
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }
}
