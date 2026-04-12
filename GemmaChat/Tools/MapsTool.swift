import UIKit

struct MapsTool: Tool {
    let name = "open_maps"
    let description = "Opens a map app with a search query. Use map parameter only when user explicitly names an app (네이버, 티맵)"
    let parameters = [
        ToolParameter("query", "Location or address to search for"),
        ToolParameter("mode", "Navigation mode: driving, walking, or transit", required: false),
        ToolParameter("map", "Map app: naver, tmap, apple. Only set when user explicitly asks", required: false)
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        guard let query = arguments["query"], !query.isEmpty else {
            return .fail("Location query is required")
        }

        let requestedMap = arguments["map"]?.lowercased()

        let provider: MapProvider
        if let req = requestedMap, let p = MapProvider(rawValue: req) {
            provider = p
        } else {
            provider = await MainActor.run { AppSettings.shared.preferredMapProvider }
        }

        let installed = await isAppInstalled(scheme: provider.urlScheme)
        let finalProvider = installed ? provider : .apple

        guard let url = buildURL(provider: finalProvider, query: query, mode: arguments["mode"]) else {
            return .fail("Failed to create map URL")
        }

        let appName = finalProvider.displayName
        let fallbackNote = (!installed && provider != .apple) ? " (\(provider.displayName) 미설치로 Apple 지도 사용)" : ""
        return .ok("\(appName)에서 열기: \(query)\(fallbackNote)", action: .openURL(url))
    }

    private func buildURL(provider: MapProvider, query: String, mode: String?) -> URL? {
        switch provider {
        case .apple:
            var components = URLComponents(string: "maps://")!
            var items = [URLQueryItem(name: "q", value: query)]
            if let dirflg = modeToAppleDirflg(mode) {
                items.append(URLQueryItem(name: "dirflg", value: dirflg))
            }
            components.queryItems = items
            return components.url

        case .naver:
            var components = URLComponents(string: "nmap://search")!
            var items = [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "appname", value: "com.nova.gemmachat")
            ]
            if let m = mode?.lowercased(), m == "driving" || m == "transit" || m == "walking" {
                // Naver Maps navigation: use route instead of search
                components = URLComponents(string: "nmap://route/car")!
                items = [
                    URLQueryItem(name: "dname", value: query),
                    URLQueryItem(name: "appname", value: "com.nova.gemmachat")
                ]
            }
            components.queryItems = items
            return components.url

        case .tmap:
            var components = URLComponents(string: "tmap://search")!
            components.queryItems = [URLQueryItem(name: "name", value: query)]
            return components.url
        }
    }

    private func modeToAppleDirflg(_ mode: String?) -> String? {
        switch mode?.lowercased() {
        case "driving": return "d"
        case "walking": return "w"
        case "transit": return "r"
        default: return nil
        }
    }

    private func isAppInstalled(scheme: String) async -> Bool {
        await MainActor.run {
            guard let url = URL(string: "\(scheme)://") else { return false }
            return UIApplication.shared.canOpenURL(url)
        }
    }
}
