import Foundation

enum AgentEvent: Equatable {
    case textDelta(String)
    case toolCallStart(name: String, arguments: [String: String])
    case toolCallResult(name: String, success: Bool, output: String)
    case actionRequired(ToolAction)
    case error(String)
    case finished
}
