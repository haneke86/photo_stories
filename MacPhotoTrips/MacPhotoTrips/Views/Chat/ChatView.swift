import SwiftUI

/// Main chat tab view — conversation with Claude about travel data.
struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        ZStack {
            DesignTokens.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Travel Chat")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    if !viewModel.messages.isEmpty {
                        Button {
                            viewModel.clearHistory()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().overlay(DesignTokens.glassBorder)

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if viewModel.messages.isEmpty && !viewModel.isStreaming {
                                emptyState
                            }

                            ForEach(viewModel.messages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }

                            // Streaming message
                            if viewModel.isStreaming && !viewModel.streamingText.isEmpty {
                                MessageBubbleView(
                                    message: ChatMessage(role: "assistant", content: viewModel.streamingText),
                                    isStreaming: true
                                )
                                .id("streaming")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.streamingText) { _, _ in
                        withAnimation {
                            proxy.scrollTo("streaming", anchor: .bottom)
                        }
                    }
                }

                Divider().overlay(DesignTokens.glassBorder)

                // Input bar
                inputBar
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            Image(systemName: "globe.europe.africa")
                .font(.system(size: 48))
                .foregroundStyle(DesignTokens.gradient)

            Text("Ask me anything about your travels")
                .font(.headline)
                .foregroundStyle(.white)

            if !viewModel.isAvailable {
                Text("No API key configured. Set ANTHROPIC_API_KEY before building.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.suggestions, id: \.self) { suggestion in
                        Button {
                            viewModel.sendSuggestion(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.teal)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(DesignTokens.teal.opacity(0.1))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(DesignTokens.teal.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Message...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial.opacity(0.3))
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(DesignTokens.glassBorder, lineWidth: 1)
                )
                .lineLimit(1...5)
                .onSubmit { viewModel.send() }

            Button {
                viewModel.send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isStreaming
                            ? DesignTokens.textTertiary
                            : DesignTokens.teal
                    )
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isStreaming)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
