import UIKit

struct SettingsTool: Tool {
    let name = "open_settings"
    let description = "Opens the Settings app"
    let parameters = [
        ToolParameter("section", "Settings section: wifi, bluetooth, cellular, general, etc.", required: false)
    ]

    private let sections: [String: String] = [
        "wifi": "App-Prefs:WIFI",
        "bluetooth": "App-Prefs:Bluetooth",
        "cellular": "App-Prefs:MOBILE_DATA_SETTINGS_ID",
        "notifications": "App-Prefs:NOTIFICATIONS_ID",
        "sounds": "App-Prefs:Sounds",
        "display": "App-Prefs:DISPLAY",
        "wallpaper": "App-Prefs:Wallpaper",
        "general": "App-Prefs:General",
        "privacy": "App-Prefs:Privacy",
        "battery": "App-Prefs:BATTERY_USAGE",
        "storage": "App-Prefs:CASTLE",
        "accessibility": "App-Prefs:ACCESSIBILITY"
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        let section = arguments["section"]?.lowercased() ?? ""

        // Try section-specific URL first, fall back to app settings
        let url: URL
        if !section.isEmpty, let sectionURL = sections[section], let parsed = URL(string: sectionURL) {
            let canOpen = await MainActor.run { UIApplication.shared.canOpenURL(parsed) }
            if canOpen {
                url = parsed
            } else {
                url = URL(string: UIApplication.openSettingsURLString)!
            }
        } else {
            url = URL(string: UIApplication.openSettingsURLString)!
        }

        let label = section.isEmpty ? "설정" : section
        return .ok("설정 열기: \(label)", action: .openURL(url))
    }
}
