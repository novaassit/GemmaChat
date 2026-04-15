import UIKit

struct ClipboardTool: Tool {
    let name = "clipboard"
    let description = "Reads from or writes to the device clipboard"
    let parameters = [
        ToolParameter("action", "Action to perform: read or write"),
        ToolParameter("text", "Text to copy to clipboard (required for write)", required: false)
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        guard let action = arguments["action"]?.lowercased() else {
            return .fail("Action is required (read or write)")
        }

        switch action {
        case "read":
            let content = await MainActor.run {
                UIPasteboard.general.string
            }
            if let content, !content.isEmpty {
                return .ok("Clipboard contents: \(content)")
            } else {
                return .ok("클립보드가 비어있습니다")
            }

        case "write":
            guard let text = arguments["text"], !text.isEmpty else {
                return .fail("Text is required for write action")
            }
            await MainActor.run {
                UIPasteboard.general.string = text
            }
            return .ok("Copied to clipboard: \(text)")

        default:
            return .fail("Invalid action: \(action). Use 'read' or 'write'.")
        }
    }
}
