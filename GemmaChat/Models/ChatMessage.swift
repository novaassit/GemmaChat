import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date
    let kind: Kind

    enum Role: String {
        case user
        case assistant
        case system
    }

    enum Kind: Equatable {
        case text
        case toolCall(name: String)
        case toolResult(name: String, success: Bool)
    }

    init(role: Role, content: String, kind: Kind = .text) {
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.kind = kind
    }
}
