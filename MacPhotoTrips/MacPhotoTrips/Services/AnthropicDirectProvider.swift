import Foundation

/// Direct Anthropic API calls via URLSession.
/// Handles both structured output (narratives) and SSE streaming (chat).
final class AnthropicDirectProvider: LLMProvider {
    private let apiKey: String
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let narrativeModel = "claude-sonnet-4-5-20250929"
    private let chatModel = "claude-sonnet-4-5-20250929"

    var isAvailable: Bool { !apiKey.isEmpty }

    init?(apiKey: String? = APIKeyConfig.apiKey) {
        guard let key = apiKey, !key.isEmpty, key != "$(ANTHROPIC_API_KEY)" else { return nil }
        self.apiKey = key
    }

    // MARK: - Narratives (structured output)

    func generateNarratives(compactTimeline: [String: Any]) async throws -> NarrativeResult {
        let timelineJSON = try JSONSerialization.data(withJSONObject: compactTimeline, options: [.prettyPrinted, .sortedKeys])
        let timelineString = String(data: timelineJSON, encoding: .utf8) ?? "{}"

        let systemPrompt = """
        You are a travel storyteller writing brief, evocative descriptions of someone's trips.

        STYLE RULES:
        - Write in second person ("You spent...", "You explored...")
        - Be warm but concise — no fluff or filler
        - Reference specific cities, seasons, and durations
        - Taglines should be 5-8 words, evocative and poetic (e.g. "Island-hopping through the Aegean blue")
        - Trip narratives: 1-3 sentences capturing the essence of the trip
        - Year narratives: 2-4 sentences summarizing the year's travel pattern
        - Use seasonal language when relevant (summer, winter, spring adventures)
        - For multi-city trips, mention the journey between places
        - Keep the tone personal and reflective, like a travel journal

        IMPORTANT:
        - You MUST provide a narrative and tagline for EVERY trip in the input
        - You MUST provide a narrative for EVERY year in the input
        - The trip_id must match exactly the 'id' field from the input trips
        - The year must match exactly the 'year' field from the input years

        Respond with ONLY valid JSON matching this exact schema:
        {
          "trip_narratives": [{"trip_id": "...", "narrative": "...", "tagline": "..."}],
          "year_narratives": [{"year": 2024, "narrative": "..."}]
        }
        """

        let userMessage = "Here is a complete travel timeline. Please write a narrative and tagline for each trip, and a narrative for each year.\n\n```json\n\(timelineString)\n```"

        let body: [String: Any] = [
            "model": narrativeModel,
            "max_tokens": 8192,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userMessage]]
        ]

        let data = try await makeRequest(body: body)
        let response = try JSONDecoder().decode(AnthropicResponse.self, from: data)

        guard let text = response.content.first?.text else {
            throw LLMError.emptyResponse
        }

        // Parse the JSON from Claude's response (may be wrapped in ```json blocks)
        let cleanJSON = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanJSON.data(using: .utf8) else {
            throw LLMError.invalidJSON
        }

        return try JSONDecoder().decode(NarrativeResult.self, from: jsonData)
    }

    // MARK: - Single Story

    func generateSingleStory(systemPrompt: String, userMessage: String) async throws -> StoryResponse {
        let body: [String: Any] = [
            "model": narrativeModel,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userMessage]]
        ]

        let data = try await makeRequest(body: body)
        let response = try JSONDecoder().decode(AnthropicResponse.self, from: data)

        guard let text = response.content.first?.text else {
            throw LLMError.emptyResponse
        }

        let cleanJSON = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanJSON.data(using: .utf8) else {
            throw LLMError.invalidJSON
        }

        return try JSONDecoder().decode(StoryResponse.self, from: jsonData)
    }

    // MARK: - Streaming Chat

    func streamChat(messages: [[String: String]], systemPrompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let body: [String: Any] = [
                        "model": chatModel,
                        "max_tokens": 1024,
                        "stream": true,
                        "system": systemPrompt,
                        "messages": messages
                    ]

                    let request = try self.buildRequest(body: body)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw LLMError.httpError(statusCode)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]" else { break }

                        guard let data = jsonString.data(using: .utf8),
                              let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else {
                            continue
                        }

                        if event.type == "content_block_delta",
                           let delta = event.delta,
                           delta.type == "text_delta",
                           let text = delta.text {
                            continuation.yield(text)
                        }

                        if event.type == "message_stop" {
                            break
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers

    private func buildRequest(body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func makeRequest(body: [String: Any]) async throws -> Data {
        let request = try buildRequest(body: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw LLMError.httpError(statusCode, errorBody)
        }

        return data
    }
}

// MARK: - Response Models

private struct AnthropicResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}

private struct StreamEvent: Decodable {
    let type: String
    let delta: Delta?

    struct Delta: Decodable {
        let type: String?
        let text: String?
    }
}

enum LLMError: LocalizedError {
    case emptyResponse
    case invalidJSON
    case httpError(Int, String = "")
    case noAPIKey
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .emptyResponse: return "Empty response from Claude"
        case .invalidJSON: return "Invalid JSON in Claude response"
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .noAPIKey: return "No Anthropic API key configured"
        case .rateLimited: return "Monthly usage limit reached"
        }
    }
}
