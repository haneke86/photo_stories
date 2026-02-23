import Foundation

/// Manages chat state: messages, streaming, history persistence.
/// Port of chat.py + server.py chat endpoint.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isStreaming = false
    @Published var streamingText = ""
    @Published var usageInfo: UsageInfo?

    private let provider: LLMProvider?
    private let systemPrompt: String

    /// Suggested prompts for empty state.
    let suggestions = [
        "What was my longest trip?",
        "Which countries did I visit in 2024?",
        "Compare my summer trips",
    ]

    init(timeline: Timeline, provider: LLMProvider? = nil) {
        self.provider = provider ?? AnthropicDirectProvider()
        self.systemPrompt = Self.buildSystemPrompt(timeline: timeline)
        self.messages = ChatHistoryStore.load()
    }

    var isAvailable: Bool { provider?.isAvailable ?? false }

    /// Whether the chat limit has been reached.
    var isAtChatLimit: Bool {
        usageInfo?.chats.isAtLimit ?? false
    }

    /// Human-readable remaining chats text.
    var remainingChatsText: String? {
        guard let info = usageInfo else { return nil }
        return "\(info.chats.remaining) of \(info.chats.limit) messages remaining"
    }

    /// Fetch current usage from the backend.
    func refreshUsage() async {
        guard let backend = provider as? BackendProvider else { return }
        usageInfo = try? await backend.fetchUsage()
    }

    /// Send a message and stream the response.
    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, !isAtChatLimit else { return }

        inputText = ""
        let userMessage = ChatMessage(role: "user", content: text)
        messages.append(userMessage)

        Task { await streamResponse() }
    }

    /// Send a suggested prompt.
    func sendSuggestion(_ suggestion: String) {
        inputText = suggestion
        send()
    }

    /// Clear conversation history.
    func clearHistory() {
        messages.removeAll()
        ChatHistoryStore.clear()
    }

    // MARK: - Streaming

    private func streamResponse() async {
        guard let provider else { return }

        isStreaming = true
        streamingText = ""

        // Build messages array for API (last 20)
        let apiMessages = messages.suffix(20).map { msg in
            ["role": msg.role, "content": msg.content]
        }

        do {
            let stream = provider.streamChat(messages: apiMessages, systemPrompt: systemPrompt)
            for try await token in stream {
                streamingText += token
            }

            // Finalize
            let assistantMessage = ChatMessage(role: "assistant", content: streamingText)
            messages.append(assistantMessage)
            streamingText = ""
            ChatHistoryStore.save(messages)
        } catch LLMError.rateLimited {
            let errorMessage = ChatMessage(role: "assistant", content: "You've reached your monthly chat limit. It resets on the 1st of next month.")
            messages.append(errorMessage)
            await refreshUsage()
        } catch {
            let errorMessage = ChatMessage(role: "assistant", content: "Sorry, I encountered an error: \(error.localizedDescription)")
            messages.append(errorMessage)
        }

        isStreaming = false
    }

    // MARK: - System Prompt (port of chat.py:build_system_prompt)

    private static func buildSystemPrompt(timeline: Timeline) -> String {
        let home = timeline.homeBase
        let summary = timeline.summary
        let dateRange = timeline.dateRange

        // Encode full timeline as JSON context
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let timelineJSON: String
        if let data = try? encoder.encode(timeline) {
            timelineJSON = String(data: data, encoding: .utf8) ?? "{}"
        } else {
            timelineJSON = "{}"
        }

        return """
        You are a friendly travel assistant who knows everything about the user's travel history.

        The user lives in \(home.city), \(home.country). Their travel data covers \(dateRange.from) to \(dateRange.to).

        Summary: \(summary.totalTrips) trips, \(summary.countriesVisited) countries, \(summary.citiesVisited) cities, \(summary.totalDaysTraveling) days traveling.

        Here is their complete travel timeline data:

        ```json
        \(timelineJSON)
        ```

        RULES:
        - Answer questions about their travel history based on the data above
        - Be conversational and warm, like a friend who remembers all their trips
        - Use specific dates, cities, and durations from the data
        - If asked about something not in the data, say so honestly
        - You can calculate statistics, compare trips, find patterns
        - Reference trip narratives and taglines if they exist in the data
        - Keep answers concise but complete
        """
    }
}
