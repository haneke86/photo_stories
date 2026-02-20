import SwiftUI

/// Chat message bubble — user (right, teal tint) or assistant (left, glass).
struct MessageBubbleView: View {
    let message: ChatMessage
    let isStreaming: Bool

    init(message: ChatMessage, isStreaming: Bool = false) {
        self.message = message
        self.isStreaming = isStreaming
    }

    private var isUser: Bool { message.role == "user" }

    /// Parse markdown in assistant messages; user messages stay plain text.
    private var renderedContent: Text {
        let raw = message.content + (isStreaming ? " \u{2588}" : "")
        if isUser {
            return Text(raw)
        }
        // Convert markdown for assistant responses (bold, italic, lists, etc.)
        if let attributed = try? AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(raw)
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                renderedContent
                    .font(.body)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isUser
                    ? AnyShapeStyle(DesignTokens.teal.opacity(0.15))
                    : AnyShapeStyle(.ultraThinMaterial.opacity(0.5))
            )
            .background(isUser ? Color.clear : Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isUser ? DesignTokens.teal.opacity(0.2) : DesignTokens.glassBorder,
                        lineWidth: 1
                    )
            )

            if !isUser { Spacer(minLength: 60) }
        }
    }
}
