import SwiftUI

struct ThinkingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .opacity(phase == index ? 1.0 : 0.3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.regularMaterial)
            .clipShape(ChatBubbleShape(isUser: false))

            Spacer(minLength: 60)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    phase = (phase + 1) % 3
                }
            }
        }
    }
}
