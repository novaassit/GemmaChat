import Foundation

struct SettingsTool: Tool {
    let name = "open_settings"
    let description = "Opens the Settings app, optionally to a specific section"
    let parameters = [
        ToolParameter("section", "Settings section to open (e.g. wifi, bluetooth, general)", required: false)
    ]

    private let sections: [String: String] = [
        "wifi": "WIFI",
        "bluetooth": "Bluetooth",
        "cellular": "MOBILE_DATA_SETTINGS_ID",
        "notifications": "NOTIFICATIONS_ID",
        "sounds": "Sounds",
        "display": "DISPLAY",
        "wallpaper": "Wallpaper",
        "general": "General",
        "privacy": "Privacy",
        "battery": "BATTERY_USAGE",
        "storage": "CASTLE",
        "accessibility": "ACCESSIBILITY"
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        var urlString = "App-prefs:"

        if let section = arguments["section"]?.lowercased(), !section.isEmpty {
            if let path = sections[section] {
                urlString += path
            } else {
                urlString += section
            }
        }

        guard let url = URL(string: urlString) else {
            return .fail("Failed to create Settings URL")
        }

        let label = arguments["section"] ?? "main"
        return .ok("Opening Settings: \(label)", action: .openURL(url))
    }
}
