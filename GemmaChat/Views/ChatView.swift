import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status bar
                if !viewModel.llama.modelLoaded {
                    modelStatusBar
                }

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }

                            // Streaming response
                            if !viewModel.streamingText.isEmpty {
                                MessageBubble(
                                    message: ChatMessage(role: .assistant, content: viewModel.streamingText)
                                )
                                .id("streaming")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: viewModel.messages.count) {
                        withAnimation {
                            proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.streamingText) {
                        withAnimation {
                            proxy.scrollTo("streaming", anchor: .bottom)
                        }
                    }
                }

                Divider()

                // Input bar
                InputBar(
                    text: $viewModel.inputText,
                    isGenerating: viewModel.llama.isGenerating,
                    isDisabled: !viewModel.llama.modelLoaded,
                    onSend: { viewModel.sendMessage() },
                    onStop: { viewModel.stopGenerating() }
                )
            }
            .navigationTitle("Gemma Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("대화 초기화", systemImage: "trash") {
                            viewModel.clearChat()
                        }
                        Button("모델 다시 로드", systemImage: "arrow.clockwise") {
                            viewModel.reloadModel()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task {
                await viewModel.loadModelOnStart()
            }
        }
    }

    private var modelStatusBar: some View {
        HStack(spacing: 8) {
            if viewModel.llama.isLoading {
                ProgressView()
                    .controlSize(.small)
                Text("모델 로딩 중...")
            } else if let error = viewModel.llama.loadError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .lineLimit(2)
                    .font(.caption)
            } else {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.blue)
                Text("모델 파일을 앱 Documents에 넣어주세요")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}

// MARK: - ViewModel

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var streamingText = ""

    let llama = LlamaService()
    private var generateTask: Task<Void, Never>?

    private var modelPath: String? {
        // Look for GGUF file in app's Documents directory
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let files = (try? FileManager.default.contentsOfDirectory(atPath: docs.path)) ?? []
        if let gguf = files.first(where: { $0.hasSuffix(".gguf") }) {
            return docs.appendingPathComponent(gguf).path
        }

        // Also check bundle
        if let bundled = Bundle.main.path(forResource: "gemma-4-e2b", ofType: "gguf") {
            return bundled
        }

        return nil
    }

    func loadModelOnStart() async {
        guard let path = modelPath else {
            llama.loadError = "GGUF 파일을 찾을 수 없습니다. Documents 폴더에 넣어주세요."
            return
        }
        await llama.loadModel(at: path)

        if llama.modelLoaded {
            // Add system greeting
            messages.append(ChatMessage(
                role: .assistant,
                content: "안녕하세요! Gemma 4 E2B 모델이 로드되었습니다. 무엇이든 물어보세요 🤖"
            ))
        }
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        messages.append(ChatMessage(role: .user, content: text))

        generateTask = Task {
            streamingText = ""
            var fullResponse = ""

            for await piece in llama.generate(messages: messages) {
                if Task.isCancelled { break }
                streamingText += piece
                fullResponse += piece
            }

            if !fullResponse.isEmpty {
                messages.append(ChatMessage(role: .assistant, content: fullResponse))
            }
            streamingText = ""
        }
    }

    func stopGenerating() {
        generateTask?.cancel()
        if !streamingText.isEmpty {
            messages.append(ChatMessage(role: .assistant, content: streamingText))
            streamingText = ""
        }
    }

    func clearChat() {
        messages.removeAll()
        streamingText = ""
    }

    func reloadModel() {
        llama.unload()
        Task { await loadModelOnStart() }
    }
}

#Preview {
    ChatView()
}
