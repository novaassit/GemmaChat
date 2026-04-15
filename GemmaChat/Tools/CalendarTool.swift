import Foundation
import EventKit

struct ReadCalendarTool: Tool {
    let name = "read_calendar"
    let description = "Read upcoming calendar events for today or a specific date range"
    let parameters = [
        ToolParameter("days", "Number of days to look ahead (default: 1 for today)", required: false)
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        let store = EKEventStore()

        do {
            let granted = try await store.requestFullAccessToEvents()
            guard granted else {
                return .fail("캘린더 접근 권한이 거부되었습니다. 설정에서 허용해주세요.")
            }
        } catch {
            return .fail("캘린더 권한 요청 실패: \(error.localizedDescription)")
        }

        let days = Int(arguments["days"] ?? "1") ?? 1
        let start = Calendar.current.startOfDay(for: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: start) else {
            return .fail("날짜 계산 실패")
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        if events.isEmpty {
            let rangeText = days == 1 ? "오늘" : "앞으로 \(days)일간"
            return .ok("\(rangeText) 예정된 일정이 없습니다.")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d(E) HH:mm"

        let results = events.prefix(10).map { event in
            let time = event.isAllDay
                ? "\(formatter.string(from: event.startDate).components(separatedBy: " ").first ?? "") 종일"
                : formatter.string(from: event.startDate)
            var line = "[\(time)] \(event.title ?? "(제목 없음)")"
            if let location = event.location, !location.isEmpty {
                line += " @ \(location)"
            }
            return line
        }

        let countInfo = events.count > 10 ? " (총 \(events.count)건 중 10건 표시)" : ""
        return .ok(results.joined(separator: "\n") + countInfo)
    }
}

struct CreateCalendarEventTool: Tool {
    let name = "create_event"
    let description = "Create a new calendar event"
    let parameters = [
        ToolParameter("title", "Event title"),
        ToolParameter("date", "Start date/time (e.g. 2026-04-15 14:00 or tomorrow 3pm)"),
        ToolParameter("duration", "Duration in minutes (default: 60)", required: false),
        ToolParameter("location", "Event location", required: false),
        ToolParameter("notes", "Additional notes", required: false)
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        guard let title = arguments["title"], !title.isEmpty else {
            return .fail("title parameter is required")
        }
        guard let dateStr = arguments["date"], !dateStr.isEmpty else {
            return .fail("date parameter is required")
        }

        let store = EKEventStore()

        do {
            let granted = try await store.requestFullAccessToEvents()
            guard granted else {
                return .fail("캘린더 접근 권한이 거부되었습니다. 설정에서 허용해주세요.")
            }
        } catch {
            return .fail("캘린더 권한 요청 실패: \(error.localizedDescription)")
        }

        guard let startDate = DateParser.parse(dateStr) else {
            return .fail("날짜를 인식할 수 없습니다: \(dateStr). 예: 2026-04-15 14:00")
        }

        let duration = TimeInterval((Int(arguments["duration"] ?? "60") ?? 60) * 60)

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(duration)
        event.location = arguments["location"]
        event.notes = arguments["notes"]
        event.calendar = store.defaultCalendarForNewEvents

        do {
            try store.save(event, span: .thisEvent)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = "M월 d일 (E) HH:mm"
            var summary = "'\(title)' 일정을 추가했습니다. \(formatter.string(from: startDate))"
            if let loc = arguments["location"] { summary += " @ \(loc)" }
            return .ok(summary)
        } catch {
            return .fail("일정 추가 실패: \(error.localizedDescription)")
        }
    }

}
