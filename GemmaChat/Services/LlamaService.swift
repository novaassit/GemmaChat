import Foundation
import llama
import os
import UIKit

@MainActor
final class LlamaService: ObservableObject, LLMProvider {

    @Published var isLoading = false
    @Published var isGenerating = false
    var isReady: Bool { modelLoaded }
    @Published var loadError: String?
    @Published var modelLoaded = false
    @Published var runtimeWarning: String?

    private var model: OpaquePointer?   // llama_model *
    private var context: OpaquePointer? // llama_context *
    private var vocab: OpaquePointer?   // llama_vocab *

    private let maxTokens = 512
    private let contextSize: UInt32 = 4096

    // Runtime safety flags (written by notification observers, read by generation loop)
    private let abortLock = NSLock()
    nonisolated(unsafe) private var _shouldAbort = false
    nonisolated(unsafe) private var _abortReason: String?

    private var memoryWarningObserver: NSObjectProtocol?
    private var thermalObserver: NSObjectProtocol?

    // Timeout: abort a single turn if generation exceeds this many seconds
    private let generationTimeoutSeconds: TimeInterval = 60

    init() {
        setupMonitoring()
    }

    private func setupMonitoring() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.requestAbort(reason: "메모리 부족 경고로 생성을 중단했습니다")
            self?.clearKVCache()
        }

        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            let state = ProcessInfo.processInfo.thermalState
            if state == .serious || state == .critical {
                self?.requestAbort(reason: "기기가 과열되어 생성을 중단했습니다. 잠시 후 다시 시도해주세요")
            }
        }
    }

    private nonisolated func requestAbort(reason: String) {
        abortLock.lock()
        _shouldAbort = true
        _abortReason = reason
        abortLock.unlock()
        Task { @MainActor in self.runtimeWarning = reason }
    }

    private nonisolated func shouldAbort() -> (Bool, String?) {
        abortLock.lock()
        defer { abortLock.unlock() }
        return (_shouldAbort, _abortReason)
    }

    private nonisolated func resetAbort() {
        abortLock.lock()
        _shouldAbort = false
        _abortReason = nil
        abortLock.unlock()
    }

    private func clearKVCache() {
        guard let context else { return }
        llama_memory_clear(llama_get_memory(context), true)
    }

    // MARK: - Model Loading

    /// Pre-load memory check: refuse to load if available memory < model size + buffer.
    /// Buffer accounts for KV cache (~500MB at n_ctx=4096) and Metal GPU buffers.
    private static let memoryBufferBytes: UInt64 = 1_200_000_000 // 1.2GB

    private func checkMemoryAvailable(modelPath: String) -> String? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: modelPath)
        guard let fileSize = (attrs?[.size] as? NSNumber)?.uint64Value, fileSize > 0 else {
            return "모델 파일을 읽을 수 없습니다"
        }

        let available = UInt64(os_proc_available_memory())
        let required = fileSize + Self.memoryBufferBytes

        if available < required {
            let availGB = Double(available) / 1_073_741_824.0
            let needGB = Double(required) / 1_073_741_824.0
            return String(
                format: "메모리 부족: 필요 %.1fGB, 가용 %.1fGB\n다른 앱을 종료하거나 기기를 재시작한 뒤 다시 시도해주세요.",
                needGB, availGB
            )
        }
        return nil
    }

    func loadModel(at path: String) async {
        isLoading = true
        loadError = nil

        if let memoryError = checkMemoryAvailable(modelPath: path) {
            loadError = memoryError
            isLoading = false
            return
        }

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

            // Pre-check thermal state
            let thermal = ProcessInfo.processInfo.thermalState
            if thermal == .critical {
                Task { @MainActor in
                    self.runtimeWarning = "기기가 과열되어 생성을 시작할 수 없습니다. 잠시 후 다시 시도해주세요"
                }
                continuation.finish()
                return
            }

            self.resetAbort()

            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { continuation.finish(); return }

                await MainActor.run {
                    self.isGenerating = true
                    self.runtimeWarning = nil
                }
                defer { Task { @MainActor in self.isGenerating = false } }

                let startTime = Date()

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

                let stopSequences = [
                    "<end_of_turn>", "<start_of_turn>",
                    "<end_of_of_turn>", "<|end|>", "<end_turn>"
                ]
                var pendingBuffer = ""
                var textStopped = false

                for tokenIndex in 0..<self.maxTokens {
                    // Safety checks every token: memory warning, thermal, timeout
                    let (abort, reason) = self.shouldAbort()
                    if abort {
                        if let reason { continuation.yield("\n\n[\(reason)]") }
                        break
                    }
                    if tokenIndex % 16 == 0 {
                        let elapsed = Date().timeIntervalSince(startTime)
                        if elapsed > self.generationTimeoutSeconds {
                            let msg = "생성 시간이 \(Int(self.generationTimeoutSeconds))초를 초과해 중단했습니다"
                            await MainActor.run { self.runtimeWarning = msg }
                            continuation.yield("\n\n[\(msg)]")
                            break
                        }
                    }

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
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }
}
