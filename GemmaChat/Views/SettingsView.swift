import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false

    private let presets: [(name: String, endpoint: String, needsKey: Bool, modelHint: String)] = [
        ("Ollama (로컬)", "/v1/chat/completions", false, "gemma3:4b-it"),
        ("OpenAI", "https://api.openai.com/v1/chat/completions", true, "gpt-4o-mini"),
        ("Anthropic", "https://api.anthropic.com/v1/messages", true, "claude-sonnet-4-20250514"),
        ("직접 입력", "", false, "")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("LLM 서비스") {
                    Picker("모드", selection: $settings.llmMode) {
                        ForEach(LLMMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    if settings.llmMode == .remote {
                        Section {
                            ForEach(presets, id: \.name) { preset in
                                Button {
                                    applyPreset(preset)
                                } label: {
                                    HStack {
                                        Text(preset.name)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if isActivePreset(preset) {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("서비스 선택")
                        }

                        Section {
                            HStack {
                                Text("Host")
                                    .frame(width: 50, alignment: .leading)
                                    .foregroundStyle(.secondary)
                                TextField("192.168.0.10", text: $settings.remoteHost)
                                    .autocapitalization(.none)
                                    .keyboardType(.URL)
                            }

                            HStack {
                                Text("Port")
                                    .frame(width: 50, alignment: .leading)
                                    .foregroundStyle(.secondary)
                                TextField("11434", text: $settings.remotePort)
                                    .keyboardType(.numberPad)
                            }

                            HStack {
                                Text("경로")
                                    .frame(width: 50, alignment: .leading)
                                    .foregroundStyle(.secondary)
                                TextField("/v1/chat/completions", text: $settings.remotePath)
                                    .autocapitalization(.none)
                            }

                            HStack {
                                Text("URL")
                                    .frame(width: 50, alignment: .leading)
                                    .foregroundStyle(.secondary)
                                Text(settings.resolvedEndpoint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } header: {
                            Text("연결 설정")
                        }

                        Section {
                            HStack {
                                TextField("모델 이름 입력", text: $settings.remoteModelName)
                                    .autocapitalization(.none)

                                Button {
                                    Task { await fetchModels() }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.borderless)
                            }

                            if !availableModels.isEmpty {
                                ForEach(availableModels, id: \.self) { model in
                                    Button {
                                        settings.remoteModelName = model
                                    } label: {
                                        HStack {
                                            Text(model)
                                                .foregroundStyle(.primary)
                                                .font(.subheadline)
                                            Spacer()
                                            if settings.remoteModelName == model {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                    }
                                }
                            }

                            if isFetchingModels {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("모델 목록 가져오는 중...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            SecureField("API Key (선택)", text: $settings.remoteAPIKey)
                        } header: {
                            Text("모델")
                        }
                    }

                    if settings.llmMode == .local {
                        Text("Documents 폴더의 GGUF 모델을 자동으로 로드합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("기본 지도 앱") {
                    Picker("지도", selection: $settings.preferredMapProvider) {
                        ForEach(MapProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }

    private func applyPreset(_ preset: (name: String, endpoint: String, needsKey: Bool, modelHint: String)) {
        if preset.name == "Ollama (로컬)" {
            settings.remoteHost = ""
            settings.remotePort = "11434"
            settings.remotePath = "/v1/chat/completions"
            settings.remoteModelName = preset.modelHint
            settings.remoteAPIKey = ""
        } else if preset.name == "직접 입력" {
            // Keep current values
        } else {
            settings.remoteHost = ""
            settings.remotePort = ""
            settings.remotePath = preset.endpoint
            settings.remoteModelName = preset.modelHint
        }
    }

    private func isActivePreset(_ preset: (name: String, endpoint: String, needsKey: Bool, modelHint: String)) -> Bool {
        if preset.name == "Ollama (로컬)" {
            return settings.remotePath == "/v1/chat/completions" && settings.remotePort == "11434"
        }
        return settings.remotePath == preset.endpoint
    }

    private func fetchModels() async {
        let host = settings.remoteHost.isEmpty ? "localhost" : settings.remoteHost
        let port = settings.remotePort.isEmpty ? "11434" : settings.remotePort
        let urlString = "http://\(host):\(port)/api/tags"

        guard let url = URL(string: urlString) else { return }

        isFetchingModels = true
        defer { isFetchingModels = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return }

            availableModels = models.compactMap { $0["name"] as? String }.sorted()
        } catch {
            availableModels = []
        }
    }
}
