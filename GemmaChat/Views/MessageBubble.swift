import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
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
}

// Custom bubble shape with tail
struct ChatBubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let tailSize: CGFloat = 6

        var path = Path()

        if isUser {
            // Rounded rect with tail on bottom-right
            path.addRoundedRect(
                in: CGRect(x: rect.minX, y: rect.minY,
                           width: rect.width - tailSize, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius)
            )
            // Tail
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
            // Rounded rect with tail on bottom-left
            path.addRoundedRect(
                in: CGRect(x: rect.minX + tailSize, y: rect.minY,
                           width: rect.width - tailSize, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius)
            )
            // Tail
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
        MessageBubble(message: ChatMessage(role: .user, content: "안녕하세요!"))
        MessageBubble(message: ChatMessage(role: .assistant, content: "안녕하세요! 무엇을 도와드릴까요?"))
    }
    .padding()
}
