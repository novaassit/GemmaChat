import Foundation

struct FetchInfoTool: Tool {
    let name = "fetch_info"
    let description = "Search the web and return text results. Use when you need real-time or up-to-date information to answer"
    let parameters = [
        ToolParameter("query", "Search query for the information needed")
    ]

    private let maxSnippets = 5
    private let timeoutSeconds: TimeInterval = 10

    func execute(arguments: [String: String]) async -> ToolResult {
        guard let query = arguments["query"], !query.isEmpty else {
            return .fail("query parameter is required")
        }

        var components = URLComponents(string: "https://html.duckduckgo.com/html/")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        guard let url = components.url else {
            return .fail("Failed to build search URL")
        }

        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return .fail("Search request failed")
            }

            guard let html = String(data: data, encoding: .utf8) else {
                return .fail("Failed to decode search results")
            }

            let snippets = parseSnippets(from: html)

            if snippets.isEmpty {
                return .ok("'\(query)' 검색 결과를 찾을 수 없습니다.")
            }

            let result = snippets.prefix(maxSnippets).enumerated().map { i, s in
                "[\(i + 1)] \(s.title)\n\(s.snippet)"
            }.joined(separator: "\n\n")

            return .ok("검색 결과 (\(query)):\n\(result)")
        } catch {
            return .fail("Search failed: \(error.localizedDescription)")
        }
    }

    private func parseSnippets(from html: String) -> [(title: String, snippet: String)] {
        var results: [(title: String, snippet: String)] = []

        let snippetPattern = #"class="result__snippet"[^>]*>(.*?)</[atd]"#
        let titlePattern = #"class="result__a"[^>]*>(.*?)</a>"#

        let titles = extractMatches(pattern: titlePattern, from: html)
        let snippets = extractMatches(pattern: snippetPattern, from: html)

        let count = min(titles.count, snippets.count)
        for i in 0..<count {
            let title = stripHTML(titles[i]).trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = stripHTML(snippets[i]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty && !snippet.isEmpty {
                results.append((title: title, snippet: snippet))
            }
        }

        return results
    }

    private func extractMatches(pattern: String, from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let captureRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captureRange])
        }
    }

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
