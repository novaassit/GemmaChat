import Foundation

struct WebSearchTool: Tool {
    let name = "web_search"
    let description = "Searches the web using Google via Safari"
    let parameters = [
        ToolParameter("query", "Search query string")
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        guard let query = arguments["query"], !query.isEmpty else {
            return .fail("Search query is required")
        }

        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        guard let url = components.url else {
            return .fail("Failed to create search URL")
        }

        return .ok("Searching for: \(query)", action: .openURL(url))
    }
}
