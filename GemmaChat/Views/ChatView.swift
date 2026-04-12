import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !viewModel.llama.modelLoaded {
                    modelStatusBar
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }

                            if viewModel.isThinking {
                                ThinkingIndicator()
                                    .id("thinking")
                            }

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
                    .onChange(of: viewModel.isThinking) {
                        if viewModel.isThinking {
                            withAnimation {
                                proxy.scrollTo("thinking", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.streamingText) {
                        withAnimation {
                            proxy.scrollTo("streaming", anchor: .bottom)
                        }
                    }
                }

                Divider()

                InputBar(
                    text: $viewModel.inputText,
                    isGenerating: viewModel.agent.isProcessing,
                    isDisabled: !viewModel.llama.modelLoaded,
                    onSend: { viewModel.sendMessage() },
                    onStop: { viewModel.stopGenerating() }
                )
            }
            .navigationTitle("Gemma Assistant")
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
                        Divider()
                        Button("설정", systemImage: "gear") {
                            viewModel.showSettings = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showSettings) {
                SettingsView()
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
    @Published var isThinking = false
    @Published var showSettings = false

    let llama: LlamaService
    let agent: AgentService

    private var processTask: Task<Void, Never>?

    init() {
        let llamaService = LlamaService()
        self.llama = llamaService
        self.agent = AgentService(llama: llamaService)
    }

    private var modelPath: String? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let files = (try? FileManager.default.contentsOfDirectory(atPath: docs.path)) ?? []
        if let gguf = files.first(where: { $0.hasSuffix(".gguf") }) {
            return docs.appendingPathComponent(gguf).path
        }
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
            messages.append(ChatMessage(
                role: .assistant,
                content: "안녕하세요! Gemma AI 비서입니다. 앱 실행, 알림 설정, 길 안내 등 다양한 작업을 도와드릴 수 있어요. 무엇을 해드릴까요?"
            ))
        }
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        messages.append(ChatMessage(role: .user, content: text))
        isThinking = true

        processTask = Task {
            streamingText = ""
            var pendingAction: ToolAction?

            for await event in agent.process(messages: messages) {
                if Task.isCancelled { break }

                switch event {
                case .textDelta(let text):
                    isThinking = false
                    streamingText = text

                case .toolCallStart, .toolCallResult:
                    break

                case .actionRequired(let action):
                    isThinking = false
                    pendingAction = action

                case .error(let error):
                    isThinking = false
                    messages.append(ChatMessage(role: .assistant, content: error))

                case .finished:
                    isThinking = false
                }
            }

            if !streamingText.isEmpty {
                messages.append(ChatMessage(role: .assistant, content: streamingText))
                streamingText = ""
            }

            if case .openURL(let url) = pendingAction {
                await UIApplication.shared.open(url)
            }
        }
    }

    func stopGenerating() {
        processTask?.cancel()
        isThinking = false
        if !streamingText.isEmpty {
            messages.append(ChatMessage(role: .assistant, content: streamingText))
            streamingText = ""
        }
    }

    func clearChat() {
        messages.removeAll()
        streamingText = ""
        isThinking = false
    }

    func reloadModel() {
        llama.unload()
        Task { await loadModelOnStart() }
    }
}

#Preview {
    ChatView()
}
