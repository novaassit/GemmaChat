import Foundation

@MainActor
protocol LLMProvider: AnyObject {
    var isReady: Bool { get }
    var isGenerating: Bool { get }
    func generate(systemPrompt: String?, messages: [ChatMessage]) -> AsyncStream<String>
}
