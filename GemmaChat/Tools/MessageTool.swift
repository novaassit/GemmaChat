import Foundation

struct MessageTool: Tool {
    let name = "send_message"
    let description = "Opens the Messages app to send an SMS to a phone number"
    let parameters = [
        ToolParameter("to", "Phone number of the recipient"),
        ToolParameter("body", "Message text to send", required: false)
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        guard let to = arguments["to"], !to.isEmpty else {
            return .fail("Recipient phone number is required")
        }

        var components = URLComponents(string: "sms:\(to)")!

        if let body = arguments["body"], !body.isEmpty {
            components.queryItems = [URLQueryItem(name: "body", value: body)]
        }

        guard let url = components.url else {
            return .fail("Failed to create message URL")
        }

        return .ok("Opening Messages to \(to)", action: .openURL(url))
    }
}
