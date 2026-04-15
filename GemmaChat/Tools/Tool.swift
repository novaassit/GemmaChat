import Foundation

protocol Tool {
    var name: String { get }
    var description: String { get }
    var parameters: [ToolParameter] { get }
    func execute(arguments: [String: String]) async -> ToolResult
}

struct ToolParameter: Equatable {
    let name: String
    let description: String
    let required: Bool

    init(_ name: String, _ description: String, required: Bool = true) {
        self.name = name
        self.description = description
        self.required = required
    }
}

struct ToolResult: Equatable {
    let success: Bool
    let output: String
    let action: ToolAction

    init(success: Bool, output: String, action: ToolAction = .none) {
        self.success = success
        self.output = output
        self.action = action
    }

    static func ok(_ output: String, action: ToolAction = .none) -> ToolResult {
        ToolResult(success: true, output: output, action: action)
    }

    static func fail(_ output: String) -> ToolResult {
        ToolResult(success: false, output: output)
    }
}

enum ToolAction: Equatable {
    case none
    case openURL(URL)
}

struct ToolCall: Equatable {
    let name: String
    let arguments: [String: String]
}
