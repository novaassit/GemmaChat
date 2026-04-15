import Foundation

/// Persists chat sessions to disk for crash recovery.
enum SessionStorage {
    private static let sessionFile = "current_session.json"
    private static let cleanExitKey = "lastCleanExit"

    private static var sessionURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(sessionFile)
    }

    /// Save current messages to disk. Call whenever messages change.
    static func save(_ messages: [ChatMessage]) {
        let snapshot = messages.map { StoredMessage(from: $0) }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: sessionURL, options: .atomic)
    }

    /// Load previous session messages if any.
    static func load() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: sessionURL),
              let stored = try? JSONDecoder().decode([StoredMessage].self, from: data) else {
            return []
        }
        return stored.map { $0.toMessage() }
    }

    /// Clear the saved session (e.g., after explicit "clear chat").
    static func clear() {
        try? FileManager.default.removeItem(at: sessionURL)
    }

    /// Mark that the app exited cleanly. Called in scene/app lifecycle handlers.
    static func markCleanExit() {
        UserDefaults.standard.set(true, forKey: cleanExitKey)
    }

    /// Mark that the app is actively running (reset on startup).
    static func markRunning() {
        UserDefaults.standard.set(false, forKey: cleanExitKey)
    }

    /// Returns true if the previous session did NOT end cleanly (crash suspected).
    static func didCrashLastSession() -> Bool {
        // If key was never set, treat as clean (first launch)
        if UserDefaults.standard.object(forKey: cleanExitKey) == nil { return false }
        return !UserDefaults.standard.bool(forKey: cleanExitKey)
    }
}

private struct StoredMessage: Codable {
    let role: String
    let content: String
    let timestamp: Date
    let kindType: String
    let kindName: String?
    let kindSuccess: Bool?

    init(from message: ChatMessage) {
        self.role = message.role.rawValue
        self.content = message.content
        self.timestamp = message.timestamp
        switch message.kind {
        case .text:
            self.kindType = "text"
            self.kindName = nil
            self.kindSuccess = nil
        case .toolCall(let name):
            self.kindType = "toolCall"
            self.kindName = name
            self.kindSuccess = nil
        case .toolResult(let name, let success):
            self.kindType = "toolResult"
            self.kindName = name
            self.kindSuccess = success
        }
    }

    func toMessage() -> ChatMessage {
        let role = ChatMessage.Role(rawValue: role) ?? .assistant
        let kind: ChatMessage.Kind
        switch kindType {
        case "toolCall":
            kind = .toolCall(name: kindName ?? "")
        case "toolResult":
            kind = .toolResult(name: kindName ?? "", success: kindSuccess ?? true)
        default:
            kind = .text
        }
        return ChatMessage(role: role, content: content, kind: kind)
    }
}
