import Foundation

@MainActor
final class RemoteLLMProvider: ObservableObject, LLMProvider {
    @Published var isGenerating = false

    var isReady: Bool {
        let s = AppSettings.shared
        return s.llmMode == .remote && !s.resolvedEndpoint.isEmpty && !s.remoteModelName.isEmpty
    }

    func generate(systemPrompt: String? = nil, messages: [ChatMessage]) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { continuation.finish(); return }

                let settings = await MainActor.run { AppSettings.shared }
                let endpoint = await MainActor.run { settings.resolvedEndpoint }
                let apiKey = await MainActor.run { settings.remoteAPIKey }
                let modelName = await MainActor.run { settings.remoteModelName }

                guard !endpoint.isEmpty else {
                    continuation.finish()
                    return
                }

                await MainActor.run { self.isGenerating = true }
                defer { Task { @MainActor in self.isGenerating = false } }

                var apiMessages: [[String: String]] = []

                if let sys = systemPrompt {
                    apiMessages.append(["role": "system", "content": sys])
                }

                for msg in messages {
                    let role: String
                    switch msg.role {
                    case .user: role = "user"
                    case .assistant: role = "assistant"
                    case .system: role = "system"
                    }
                    apiMessages.append(["role": role, "content": msg.content])
                }

                let body: [String: Any] = [
                    "model": modelName,
                    "messages": apiMessages,
                    "stream": true,
                    "temperature": 0.7,
                    "top_p": 0.9
                ]

                guard let url = URL(string: endpoint),
                      let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
                    continuation.finish()
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = httpBody
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if !apiKey.isEmpty {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                }

                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        continuation.finish()
                        return
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        guard line.hasPrefix("data: ") else { continue }
                        let data = String(line.dropFirst(6))

                        if data == "[DONE]" { break }

                        guard let jsonData = data.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else {
                            continue
                        }

                        continuation.yield(content)
                    }
                } catch {
                    // Stream ended or error
                }

                continuation.finish()
            }
        }
    }
}
