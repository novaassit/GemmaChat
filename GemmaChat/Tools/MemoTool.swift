import Foundation

struct SaveMemoTool: Tool {
    let name = "save_memo"
    let description = "Save text to a memo file. The file is accessible in the Files app under GemmaChat"
    let parameters = [
        ToolParameter("title", "Memo title (used as filename)"),
        ToolParameter("content", "Text content to save")
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        guard let title = arguments["title"], !title.isEmpty else {
            return .fail("title parameter is required")
        }
        guard let content = arguments["content"], !content.isEmpty else {
            return .fail("content parameter is required")
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let memosDir = docs.appendingPathComponent("Memos")

        do {
            try FileManager.default.createDirectory(at: memosDir, withIntermediateDirectories: true)
        } catch {
            return .fail("폴더 생성 실패: \(error.localizedDescription)")
        }

        let safeTitle = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let filename = "\(safeTitle).txt"
        let fileURL = memosDir.appendingPathComponent(filename)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let header = "[\(formatter.string(from: Date()))] \(title)\n\n"

        let fullContent = header + content

        do {
            try fullContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return .ok("메모 저장 완료: '\(title)'\n파일 앱 → GemmaChat → Memos에서 확인 가능")
        } catch {
            return .fail("메모 저장 실패: \(error.localizedDescription)")
        }
    }
}

struct ReadMemoTool: Tool {
    let name = "read_memo"
    let description = "List saved memos or read a specific memo by title"
    let parameters = [
        ToolParameter("title", "Memo title to read. Leave empty to list all memos", required: false)
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let memosDir = docs.appendingPathComponent("Memos")

        guard FileManager.default.fileExists(atPath: memosDir.path) else {
            return .ok("저장된 메모가 없습니다.")
        }

        if let title = arguments["title"], !title.isEmpty {
            let safeTitle = title.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let fileURL = memosDir.appendingPathComponent("\(safeTitle).txt")

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return .fail("'\(title)' 메모를 찾을 수 없습니다.")
            }

            return .ok(content)
        }

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: memosDir.path) else {
            return .ok("저장된 메모가 없습니다.")
        }

        let memos = files.filter { $0.hasSuffix(".txt") }
            .map { $0.replacingOccurrences(of: ".txt", with: "") }

        if memos.isEmpty {
            return .ok("저장된 메모가 없습니다.")
        }

        return .ok("저장된 메모 (\(memos.count)개):\n" + memos.map { "- \($0)" }.joined(separator: "\n"))
    }
}
