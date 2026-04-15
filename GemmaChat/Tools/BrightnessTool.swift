import UIKit

struct BrightnessTool: Tool {
    let name = "set_brightness"
    let description = "Gets or sets screen brightness. Accepts 0-100 (percent) or 0.0-1.0"
    let parameters = [
        ToolParameter("level", "Brightness: 0~100 percent, or 0.0~1.0", required: false)
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        if let levelStr = arguments["level"]?.trimmingCharacters(in: .whitespaces),
           !levelStr.isEmpty {
            let cleaned = levelStr.replacingOccurrences(of: "%", with: "")
            guard var level = Float(cleaned) else {
                return .fail("밝기 값을 인식할 수 없습니다: \(levelStr)")
            }

            if level > 1.0 { level /= 100.0 }
            level = max(0.0, min(1.0, level))

            let before = await MainActor.run { Int(UIScreen.main.brightness * 100) }

            await MainActor.run {
                UIScreen.main.brightness = CGFloat(level)
            }

            let after = Int(level * 100)
            return .ok("밝기 변경: \(before)% → \(after)%")
        } else {
            let current = await MainActor.run { Int(UIScreen.main.brightness * 100) }
            return .ok("현재 밝기: \(current)%")
        }
    }
}
