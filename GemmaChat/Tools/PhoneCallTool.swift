import Foundation

struct PhoneCallTool: Tool {
    let name = "make_call"
    let description = "Makes a phone call to the specified number"
    let parameters = [
        ToolParameter("number", "Phone number to call")
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        guard let number = arguments["number"], !number.isEmpty else {
            return .fail("Phone number is required")
        }

        let cleaned = number.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")

        guard let url = URL(string: "tel:\(cleaned)") else {
            return .fail("Invalid phone number: \(number)")
        }

        return .ok("Calling \(number)", action: .openURL(url))
    }
}
