import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        switch message.kind {
        case .text:
            textBubble
        case .toolCall(let name):
            toolCallBubble(name: name)
        case .toolResult(let name, let success):
            toolResultBubble(name: name, success: success)
        }
    }

    // MARK: - Text Bubble

    private var textBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                markdownText(message.content)
                    .textSelection(.enabled)
                    .font(.body)
                    .foregroundStyle(isUser ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        isUser
                            ? AnyShapeStyle(Color.blue)
                            : AnyShapeStyle(.regularMaterial)
                    )
                    .clipShape(ChatBubbleShape(isUser: isUser))

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    // MARK: - Tool Call Bubble

    private func toolCallBubble(name: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: toolIcon(for: name))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 28, height: 28)
                .background(Color.orange.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(toolDisplayName(for: name))
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            ProgressView()
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.trailing, 60)
    }

    // MARK: - Tool Result Bubble

    private func toolResultBubble(name: String, success: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(success ? .green : .red)
                .frame(width: 28, height: 28)
                .background((success ? Color.green : Color.red).opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(toolDisplayName(for: name))
                    .font(.caption.bold())
                    .foregroundStyle(success ? .green : .red)
                Text(message.content)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background((success ? Color.green : Color.red).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.trailing, 60)
    }

    // MARK: - Markdown Rendering

    private func markdownText(_ content: String) -> Text {
        if let attributed = try? AttributedString(markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(content)
    }

    // MARK: - Tool Metadata

    private func toolIcon(for name: String) -> String {
        switch name {
        case "open_app": return "app.badge"
        case "web_search": return "magnifyingglass"
        case "get_datetime": return "clock"
        case "get_device_info": return "iphone"
        case "clipboard": return "doc.on.clipboard"
        case "open_maps": return "map"
        case "send_message": return "message"
        case "make_call": return "phone"
        case "open_settings": return "gear"
        case "run_shortcut": return "bolt.fill"
        case "create_reminder": return "bell"
        case "set_brightness": return "sun.max"
        case "search_contacts": return "person.crop.circle"
        case "add_contact": return "person.crop.circle.badge.plus"
        case "fetch_info": return "globe"
        case "read_calendar": return "calendar"
        case "create_event": return "calendar.badge.plus"
        case "save_memo": return "square.and.pencil"
        case "read_memo": return "doc.text"
        default: return "wrench"
        }
    }

    private func toolDisplayName(for name: String) -> String {
        switch name {
        case "open_app": return "앱 실행"
        case "web_search": return "웹 검색"
        case "get_datetime": return "날짜/시간"
        case "get_device_info": return "기기 정보"
        case "clipboard": return "클립보드"
        case "open_maps": return "지도"
        case "send_message": return "메시지"
        case "make_call": return "전화"
        case "open_settings": return "설정"
        case "run_shortcut": return "단축어"
        case "create_reminder": return "미리알림"
        case "set_brightness": return "밝기"
        case "search_contacts": return "연락처 검색"
        case "add_contact": return "연락처 추가"
        case "fetch_info": return "정보 검색"
        case "read_calendar": return "일정 확인"
        case "create_event": return "일정 추가"
        case "save_memo": return "메모 저장"
        case "read_memo": return "메모 읽기"
        default: return name
        }
    }
}

// Custom bubble shape with tail
struct ChatBubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let tailSize: CGFloat = 6

        var path = Path()

        if isUser {
            path.addRoundedRect(
                in: CGRect(x: rect.minX, y: rect.minY,
                           width: rect.width - tailSize, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius)
            )
            path.move(to: CGPoint(x: rect.maxX - tailSize, y: rect.maxY - 20))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.maxX - tailSize, y: rect.maxY - 4)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - tailSize - 10, y: rect.maxY),
                control: CGPoint(x: rect.maxX - tailSize - 2, y: rect.maxY)
            )
        } else {
            path.addRoundedRect(
                in: CGRect(x: rect.minX + tailSize, y: rect.minY,
                           width: rect.width - tailSize, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius)
            )
            path.move(to: CGPoint(x: rect.minX + tailSize, y: rect.maxY - 20))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                control: CGPoint(x: rect.minX + tailSize, y: rect.maxY - 4)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + tailSize + 10, y: rect.maxY),
                control: CGPoint(x: rect.minX + tailSize + 2, y: rect.maxY)
            )
        }

        return path
    }
}

#Preview {
    VStack(spacing: 12) {
        MessageBubble(message: ChatMessage(role: .user, content: "사파리 열어줘"))
        MessageBubble(message: ChatMessage(
            role: .assistant, content: "open_app(app: Safari)",
            kind: .toolCall(name: "open_app")
        ))
        MessageBubble(message: ChatMessage(
            role: .assistant, content: "Safari를 열었습니다",
            kind: .toolResult(name: "open_app", success: true)
        ))
        MessageBubble(message: ChatMessage(
            role: .assistant, content: "사파리를 열어드렸습니다!"
        ))
    }
    .padding()
}
