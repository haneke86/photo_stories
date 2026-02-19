import Foundation

/// Narrative result from story generation — matches llm_stories.py output.
struct TripNarrative: Codable {
    let tripId: String
    let narrative: String
    let tagline: String

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case narrative, tagline
    }
}

struct YearNarrative: Codable {
    let year: Int
    let narrative: String
}

struct NarrativeResult: Codable {
    let tripNarratives: [TripNarrative]
    let yearNarratives: [YearNarrative]

    enum CodingKeys: String, CodingKey {
        case tripNarratives = "trip_narratives"
        case yearNarratives = "year_narratives"
    }
}

/// Chat message for conversation history.
struct ChatMessage: Codable, Identifiable {
    let id: UUID
    let role: String   // "user" or "assistant"
    let content: String
    let timestamp: Date

    init(role: String, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

/// Protocol for LLM providers — swappable from direct API to backend proxy.
protocol LLMProvider {
    /// Generate trip narratives + taglines and year narratives.
    func generateNarratives(compactTimeline: [String: Any]) async throws -> NarrativeResult

    /// Stream a chat response token by token.
    func streamChat(messages: [[String: String]], systemPrompt: String) -> AsyncThrowingStream<String, Error>

    /// Whether this provider is available (has API key, etc).
    var isAvailable: Bool { get }
}
