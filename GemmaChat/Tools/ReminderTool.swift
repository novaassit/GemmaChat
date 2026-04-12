import EventKit

struct ReminderTool: Tool {
    let name = "create_reminder"
    let description = "Creates a new reminder with optional due date and alert"
    let parameters = [
        ToolParameter("title", "Title of the reminder"),
        ToolParameter("notes", "Additional notes", required: false),
        ToolParameter("date", "Due date (e.g. 2026-04-15 09:00, 2026-04-15, tomorrow)", required: false)
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        guard let title = arguments["title"], !title.isEmpty else {
            return .fail("title parameter is required")
        }

        let store = EKEventStore()

        do {
            let granted = try await store.requestFullAccessToReminders()
            guard granted else {
                return .fail("미리알림 접근 권한이 거부되었습니다. 설정에서 허용해주세요.")
            }
        } catch {
            return .fail("미리알림 권한 요청 실패: \(error.localizedDescription)")
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()

        if let notes = arguments["notes"], !notes.isEmpty {
            reminder.notes = notes
        }

        var dueDateStr = ""
        if let dateString = arguments["date"], !dateString.isEmpty {
            if let date = DateParser.parse(dateString) {
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: date
                )
                reminder.dueDateComponents = components

                let alarm = EKAlarm(absoluteDate: date)
                reminder.addAlarm(alarm)

                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "ko_KR")
                formatter.dateFormat = "M월 d일 (E) HH:mm"
                dueDateStr = " 기한: \(formatter.string(from: date))"
            }
        }

        do {
            try store.save(reminder, commit: true)
            return .ok("미리알림 생성: '\(title)'\(dueDateStr)")
        } catch {
            return .fail("미리알림 저장 실패: \(error.localizedDescription)")
        }
    }

}
