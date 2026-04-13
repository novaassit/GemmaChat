import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !viewModel.activeProvider.isReady {
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
                    isDisabled: !viewModel.activeProvider.isReady,
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
            .sheet(isPresented: $viewModel.showSettings, onDismiss: {
                viewModel.applySettings()
            }) {
                SettingsView()
            }
            .task {
                await viewModel.loadModelOnStart()
            }
        }
    }

    private var modelStatusBar: some View {
        HStack(spacing: 8) {
            if viewModel.isCheckingModel {
                ProgressView()
                    .controlSize(.small)
                Text("모델 확인 중...")
                    .font(.caption)
            } else if let local = viewModel.activeProvider as? LlamaService {
                if local.isLoading {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("모델 로딩 중...")
                            .font(.caption.bold())
                        Text("잠시 기다려주세요")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let error = local.loadError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .lineLimit(2)
                        .font(.caption)
                } else {
                    Image(systemName: "doc.badge.arrow.up")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("모델 파일 필요")
                            .font(.caption.bold())
                        Text("GGUF 파일을 파일 앱 → GemmaChat에 넣어주세요")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("API 연결 필요")
                        .font(.caption.bold())
                    Text("설정에서 Endpoint와 모델을 입력해주세요")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
    @Published var isCheckingModel = true

    private let localProvider = LlamaService()
    private let remoteProvider = RemoteLLMProvider()
    private(set) var agent: AgentService!

    var activeProvider: any LLMProvider {
        AppSettings.shared.llmMode == .remote ? remoteProvider : localProvider
    }

    private var processTask: Task<Void, Never>?

    init() {
        self.agent = AgentService(provider: localProvider)
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
        let settings = AppSettings.shared
        agent = AgentService(provider: activeProvider)

        if settings.llmMode == .remote {
            isCheckingModel = false
        } else {
            guard let path = modelPath else {
                isCheckingModel = false
                localProvider.loadError = "GGUF 파일을 찾을 수 없습니다. Documents 폴더에 넣어주세요."
                return
            }
            isCheckingModel = false
            await localProvider.loadModel(at: path)
        }

        if activeProvider.isReady {
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
        localProvider.unload()
        Task { await loadModelOnStart() }
    }

    func applySettings() {
        agent = AgentService(provider: activeProvider)
        clearChat()
        if activeProvider.isReady {
            messages.append(ChatMessage(
                role: .assistant,
                content: "안녕하세요! Gemma AI 비서입니다. 무엇을 해드릴까요?"
            ))
        } else if AppSettings.shared.llmMode == .local {
            isCheckingModel = true
            Task { await loadModelOnStart() }
        }
        objectWillChange.send()
    }
}

#Preview {
    ChatView()
}
