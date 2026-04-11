import SwiftUI

struct InputBar: View {
    @Binding var text: String
    let isGenerating: Bool
    let isDisabled: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Text field
            TextField("메시지 입력...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isFocused)
                .disabled(isDisabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(.regularMaterial)
                )
                .onSubmit {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend()
                    }
                }

            // Send / Stop button
            Button {
                if isGenerating {
                    onStop()
                } else {
                    onSend()
                    isFocused = false
                }
            } label: {
                Image(systemName: isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(buttonColor)
            }
            .disabled(isDisabled || (!isGenerating && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            .animation(.easeInOut(duration: 0.15), value: isGenerating)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var buttonColor: Color {
        if isGenerating { return .red }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDisabled {
            return .gray.opacity(0.5)
        }
        return .blue
    }
}

#Preview {
    VStack {
        Spacer()
        InputBar(
            text: .constant("테스트 메시지"),
            isGenerating: false,
            isDisabled: false,
            onSend: {},
            onStop: {}
        )
    }
}
