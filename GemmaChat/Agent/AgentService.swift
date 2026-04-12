import Foundation

@MainActor
final class AgentService: ObservableObject {
    let provider: any LLMProvider
    let toolRegistry: ToolRegistry

    @Published var isProcessing = false

    private let maxToolIterations = 5

    init(provider: any LLMProvider, toolRegistry: ToolRegistry = .createDefault()) {
        self.provider = provider
        self.toolRegistry = toolRegistry
    }

    func process(messages: [ChatMessage]) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { continuation.finish(); return }

                await MainActor.run { self.isProcessing = true }
                defer { Task { @MainActor in self.isProcessing = false } }

                var conversationMessages = messages
                let systemPromptText = AgentPrompt.systemPrompt(
                    toolDescriptions: self.toolRegistry.systemPromptDescription()
                )

                var iteration = 0
                var reachedLimit = false

                while iteration < self.maxToolIterations {
                    iteration += 1
                    var fullResponse = ""

                    let stream = await MainActor.run {
                        self.provider.generate(systemPrompt: systemPromptText, messages: conversationMessages)
                    }
                    for await piece in stream {
                        if Task.isCancelled { break }
                        fullResponse += piece
                    }

                    if Task.isCancelled { break }

                    let parsed = self.parseResponse(fullResponse)

                    if !parsed.text.isEmpty {
                        continuation.yield(.textDelta(parsed.text))
                    }

                    guard let toolCall = parsed.toolCall else {
                        break
                    }

                    guard let tool = self.toolRegistry.get(toolCall.name) else {
                        continuation.yield(.error("알 수 없는 도구: \(toolCall.name)"))
                        break
                    }

                    continuation.yield(.toolCallStart(
                        name: toolCall.name,
                        arguments: toolCall.arguments
                    ))

                    let result = await tool.execute(arguments: toolCall.arguments)

                    continuation.yield(.toolCallResult(
                        name: toolCall.name,
                        success: result.success,
                        output: result.output
                    ))

                    if result.action != .none {
                        continuation.yield(.actionRequired(result.action))
                    }

                    // For data-returning tools (no URL action), show the result directly
                    // instead of re-calling the LLM, which often produces empty responses.
                    if result.action == .none && result.success {
                        continuation.yield(.textDelta(result.output))
                        break
                    }

                    // For URL-opening tools, no need to re-call LLM either.
                    break
                }

                continuation.yield(.finished)
                continuation.finish()
            }
        }
    }

    // MARK: - Multi-Format Response Parsing

    private nonisolated func parseResponse(_ response: String) -> ParsedResponse {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Format 1: <tool_call>{"name":"...", "args":{...}}</tool_call>
        if let result = parseXMLFormat(trimmed) { return result }

        // Format 2: tool_name(key: value, key: value)  or  tool_name(key=value, key=value)
        if let result = parseFunctionCallFormat(trimmed) { return result }

        // Format 3: [TOOL] name key=value
        if let result = parseBracketFormat(trimmed) { return result }

        return ParsedResponse(text: trimmed, toolCall: nil)
    }

    private nonisolated func parseXMLFormat(_ response: String) -> ParsedResponse? {
        guard let startRange = response.range(of: "<tool_call>"),
              let endRange = response.range(of: "</tool_call>") else {
            return nil
        }

        let textBefore = String(response[..<startRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonStr = String(response[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else {
            return nil
        }

        var arguments: [String: String] = [:]
        if let args = json["args"] as? [String: Any] {
            for (key, value) in args { arguments[key] = "\(value)" }
        }

        return ParsedResponse(text: textBefore, toolCall: ToolCall(name: name, arguments: arguments))
    }

    private nonisolated func parseFunctionCallFormat(_ response: String) -> ParsedResponse? {
        let knownTools = Set([
            "open_app", "web_search", "open_maps", "send_message", "make_call",
            "open_settings", "run_shortcut", "get_datetime", "get_device_info",
            "clipboard", "create_reminder", "set_brightness", "search_contacts",
            "add_contact", "fetch_info", "read_calendar", "create_event",
            "save_memo", "read_memo"
        ])

        // Match: tool_name(args) at any position in the response
        // Pattern: word_word(anything)
        let pattern = #"(\w+)\(([^)]*)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: response,
                range: NSRange(response.startIndex..., in: response)
              ) else {
            return nil
        }

        guard let nameRange = Range(match.range(at: 1), in: response),
              let argsRange = Range(match.range(at: 2), in: response) else {
            return nil
        }

        let name = String(response[nameRange])
        guard knownTools.contains(name) else { return nil }

        let argsStr = String(response[argsRange])
        var arguments: [String: String] = [:]

        // Parse "key: value" or "key=value" pairs
        let argParts = argsStr.components(separatedBy: ",")
        for part in argParts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            let separators: [Character] = [":", "="]
            for sep in separators {
                if let sepIndex = trimmed.firstIndex(of: sep) {
                    let key = trimmed[..<sepIndex].trimmingCharacters(in: .whitespaces)
                    let value = trimmed[trimmed.index(after: sepIndex)...]
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !key.isEmpty {
                        arguments[key] = value
                    }
                    break
                }
            }
        }

        let fullMatchRange = Range(match.range, in: response)!
        let textBefore = String(response[..<fullMatchRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedResponse(text: textBefore, toolCall: ToolCall(name: name, arguments: arguments))
    }

    private nonisolated func parseBracketFormat(_ response: String) -> ParsedResponse? {
        guard let toolRange = response.range(of: "[TOOL]") ?? response.range(of: "[tool]") else {
            return nil
        }

        let textBefore = String(response[..<toolRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = String(response[toolRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = rest.components(separatedBy: " ")
        guard let name = parts.first, !name.isEmpty else { return nil }

        var arguments: [String: String] = [:]
        for part in parts.dropFirst() {
            if let eqIdx = part.firstIndex(of: "=") {
                let key = String(part[..<eqIdx])
                let value = String(part[part.index(after: eqIdx)...])
                arguments[key] = value
            }
        }

        return ParsedResponse(text: textBefore, toolCall: ToolCall(name: name, arguments: arguments))
    }
}

private struct ParsedResponse {
    let text: String
    let toolCall: ToolCall?
}
