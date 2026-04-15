import Foundation

struct AppLauncherTool: Tool {
    let name = "open_app"
    let description = "Opens an app on the device by name or URL scheme"
    let parameters = [
        ToolParameter("app", "Name of the app to open (e.g. Safari, Maps, Camera)")
    ]

    private let schemes: [String: String] = [
        "safari": "x-web-search://",
        "maps": "maps://",
        "mail": "mailto:",
        "messages": "sms:",
        "phone": "tel:",
        "camera": "camera://",
        "photos": "photos-redirect://",
        "music": "music://",
        "podcasts": "podcasts://",
        "notes": "mobilenotes://",
        "reminders": "x-apple-reminderkit://",
        "calendar": "calshow://",
        "clock": "clock-worldclock://",
        "weather": "weather://",
        "calculator": "calc://",
        "settings": "App-prefs:",
        "app store": "itms-apps://",
        "facetime": "facetime://",
        "files": "shareddocuments://",
        "wallet": "shoebox://",
        "health": "x-apple-health://",
        "shortcuts": "shortcuts://",
        "news": "applenews://",
        "books": "ibooks://",
        "home": "com.apple.home://",
        "fitness": "fitnessapp://",
        "translate": "translate://",
        "compass": "compass://",
        "contacts": "contacts://",
        "find my": "findmy://",
        "voice memos": "voicememos://",
        "measure": "measure://",
        "magnifier": "magnifier://",
        "tips": "x-apple-tips://",
        "stocks": "stocks://"
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        guard let app = arguments["app"], !app.isEmpty else {
            return .fail("App name is required")
        }

        let key = app.lowercased().trimmingCharacters(in: .whitespaces)
        let urlString: String

        if let scheme = schemes[key] {
            urlString = scheme
        } else if let url = URL(string: key), url.scheme != nil {
            urlString = key
        } else {
            return .fail("Unknown app: \(app). Try providing a URL scheme directly.")
        }

        guard let url = URL(string: urlString) else {
            return .fail("Invalid URL scheme for app: \(app)")
        }

        return .ok("Opening \(app)", action: .openURL(url))
    }
}
