import UIKit

struct BrightnessTool: Tool {
    let name = "set_brightness"
    let description = "Gets or sets the screen brightness level (0.0 to 1.0)"
    let parameters = [
        ToolParameter("level", "Brightness level from 0.0 (darkest) to 1.0 (brightest)", required: false)
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        if let levelStr = arguments["level"], !levelStr.isEmpty {
            guard let level = Float(levelStr), level >= 0.0, level <= 1.0 else {
                return .fail("Brightness level must be a number between 0.0 and 1.0")
            }

            await MainActor.run {
                UIScreen.main.brightness = CGFloat(level)
            }
            return .ok("Brightness set to \(Int(level * 100))%")
        } else {
            let current = await MainActor.run {
                UIScreen.main.brightness
            }
            return .ok("Current brightness: \(Int(current * 100))%")
        }
    }
}
