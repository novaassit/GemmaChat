import Foundation

struct ShortcutTool: Tool {
    let name = "run_shortcut"
    let description = "Runs a Shortcuts automation by name with optional input"
    let parameters = [
        ToolParameter("name", "Name of the shortcut to run"),
        ToolParameter("input", "Input text to pass to the shortcut", required: false)
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        guard let name = arguments["name"], !name.isEmpty else {
            return .fail("Shortcut name is required")
        }

        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return .fail("Failed to encode shortcut name")
        }

        var urlString = "shortcuts://run-shortcut?name=\(encodedName)"

        if let input = arguments["input"],
           let encodedInput = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "&input=\(encodedInput)"
        }

        guard let url = URL(string: urlString) else {
            return .fail("Failed to create Shortcuts URL")
        }

        return .ok("Running shortcut: \(name)", action: .openURL(url))
    }
}
