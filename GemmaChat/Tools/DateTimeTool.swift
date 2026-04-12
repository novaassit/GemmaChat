import Foundation

struct DateTimeTool: Tool {
    let name = "get_datetime"
    let description = "Returns the current date, time, and timezone"
    let parameters: [ToolParameter] = []

    func execute(arguments: [String: String]) async -> ToolResult {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 EEEE a h시 m분 s초"
        let dateString = formatter.string(from: Date())

        let timezone = TimeZone.current
        let tzName = timezone.localizedName(for: .standard, locale: Locale(identifier: "ko_KR")) ?? timezone.identifier
        let offsetSeconds = timezone.secondsFromGMT()
        let hours = offsetSeconds / 3600
        let sign = hours >= 0 ? "+" : ""

        return .ok("\(dateString)\nTimezone: \(tzName) (UTC\(sign)\(hours))")
    }
}
