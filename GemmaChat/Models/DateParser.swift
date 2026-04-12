import Foundation

enum DateParser {
    static func parse(_ str: String) -> Date? {
        let trimmed = str.trimmingCharacters(in: .whitespaces)

        // Relative dates: 오늘, 내일, 모레, 다음주 등
        if let date = parseRelative(trimmed) {
            return date
        }

        // Absolute formats
        let formats = [
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy/MM/dd HH:mm",
            "yyyy-MM-dd",
            "MM/dd HH:mm",
            "M월 d일 HH:mm",
            "M월 d일"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                var components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: date
                )
                if components.year == nil || components.year! < 2000 {
                    components.year = Calendar.current.component(.year, from: Date())
                }
                if components.hour == nil {
                    components.hour = 9
                    components.minute = 0
                }
                return Calendar.current.date(from: components)
            }
        }

        return nil
    }

    private static func parseRelative(_ str: String) -> Date? {
        let cal = Calendar.current
        let now = Date()
        var dayOffset = 0
        var hour: Int?
        var minute: Int = 0

        // Extract day offset from keywords
        if str.contains("오늘") {
            dayOffset = 0
        } else if str.contains("내일") {
            dayOffset = 1
        } else if str.contains("모레") || str.contains("내일모레") {
            dayOffset = 2
        } else if str.contains("다음주") || str.contains("다음 주") {
            dayOffset = 7
        } else if str.contains("이번주") || str.contains("이번 주") {
            dayOffset = 0
        } else {
            // Check for day-of-week: 월요일, 화요일, ...
            let weekdays = ["일요일": 1, "월요일": 2, "화요일": 3, "수요일": 4,
                            "목요일": 5, "금요일": 6, "토요일": 7]
            for (name, weekday) in weekdays {
                if str.contains(name) {
                    let today = cal.component(.weekday, from: now)
                    var diff = weekday - today
                    if diff <= 0 { diff += 7 }
                    dayOffset = diff
                    break
                }
            }
            if dayOffset == 0 && !str.contains("오늘") {
                // No relative keyword found — not a relative date
                return nil
            }
        }

        // Extract time: "2시", "14시", "오후 3시", "오전 10시 30분"
        let timePatterns: [(String, (String) -> (Int, Int)?)] = [
            (#"오후\s*(\d{1,2})시\s*(\d{1,2})분"#, { s in
                guard let m = try? NSRegularExpression(pattern: #"오후\s*(\d{1,2})시\s*(\d{1,2})분"#).firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                      let hRange = Range(m.range(at: 1), in: s),
                      let mRange = Range(m.range(at: 2), in: s),
                      var h = Int(s[hRange]), let min = Int(s[mRange]) else { return nil }
                if h < 12 { h += 12 }
                return (h, min)
            }),
            (#"오전\s*(\d{1,2})시\s*(\d{1,2})분"#, { s in
                guard let m = try? NSRegularExpression(pattern: #"오전\s*(\d{1,2})시\s*(\d{1,2})분"#).firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                      let hRange = Range(m.range(at: 1), in: s),
                      let mRange = Range(m.range(at: 2), in: s),
                      let h = Int(s[hRange]), let min = Int(s[mRange]) else { return nil }
                return (h, min)
            }),
            (#"오후\s*(\d{1,2})시"#, { s in
                guard let m = try? NSRegularExpression(pattern: #"오후\s*(\d{1,2})시"#).firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                      let hRange = Range(m.range(at: 1), in: s),
                      var h = Int(s[hRange]) else { return nil }
                if h < 12 { h += 12 }
                return (h, 0)
            }),
            (#"오전\s*(\d{1,2})시"#, { s in
                guard let m = try? NSRegularExpression(pattern: #"오전\s*(\d{1,2})시"#).firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                      let hRange = Range(m.range(at: 1), in: s),
                      let h = Int(s[hRange]) else { return nil }
                return (h, 0)
            }),
            (#"(\d{1,2})시\s*(\d{1,2})분"#, { s in
                guard let m = try? NSRegularExpression(pattern: #"(\d{1,2})시\s*(\d{1,2})분"#).firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                      let hRange = Range(m.range(at: 1), in: s),
                      let mRange = Range(m.range(at: 2), in: s),
                      let h = Int(s[hRange]), let min = Int(s[mRange]) else { return nil }
                return (h, min)
            }),
            (#"(\d{1,2})시"#, { s in
                guard let m = try? NSRegularExpression(pattern: #"(\d{1,2})시"#).firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                      let hRange = Range(m.range(at: 1), in: s),
                      let h = Int(s[hRange]) else { return nil }
                return (h, 0)
            }),
            (#"(\d{1,2}):(\d{2})"#, { s in
                guard let m = try? NSRegularExpression(pattern: #"(\d{1,2}):(\d{2})"#).firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                      let hRange = Range(m.range(at: 1), in: s),
                      let mRange = Range(m.range(at: 2), in: s),
                      let h = Int(s[hRange]), let min = Int(s[mRange]) else { return nil }
                return (h, min)
            })
        ]

        for (_, parser) in timePatterns {
            if let (h, m) = parser(str) {
                hour = h
                minute = m
                break
            }
        }

        let baseDate = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now))!
        var components = cal.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour ?? 9
        components.minute = minute

        return cal.date(from: components)
    }
}
