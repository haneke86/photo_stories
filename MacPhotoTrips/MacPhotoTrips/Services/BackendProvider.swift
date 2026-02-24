import Foundation
import Security

/// LLM provider that routes through our AWS backend instead of calling Anthropic directly.
/// Implements the same LLMProvider protocol — drop-in replacement for AnthropicDirectProvider.
final class BackendProvider: LLMProvider, @unchecked Sendable {
    private let authService: AuthService

    var isAvailable: Bool {
        // Check keychain directly to avoid MainActor isolation issues.
        // Keychain reads are thread-safe.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "com.macphoto.idToken",
            kSecReturnData as String: false,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    init(authService: AuthService) {
        self.authService = authService
    }

    // MARK: - Narratives (batch)

    func generateNarratives(compactTimeline: [String: Any]) async throws -> NarrativeResult {
        let token = try await requireToken()

        let timelineJSON = try JSONSerialization.data(withJSONObject: compactTimeline, options: [.prettyPrinted, .sortedKeys])
        let timelineString = String(data: timelineJSON, encoding: .utf8) ?? "{}"

        let systemPrompt = """
        You are a travel storyteller writing brief, evocative descriptions of someone's trips.

        STYLE RULES:
        - Write in second person ("You spent...", "You explored...")
        - Be warm but concise — no fluff or filler
        - Reference specific cities, seasons, and durations
        - Taglines should be 5-8 words, evocative and poetic
        - Trip narratives: 1-3 sentences capturing the essence of the trip
        - Year narratives: 2-4 sentences summarizing the year's travel pattern

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
            "systemPrompt": systemPrompt,
            "messages": [["role": "user", "content": userMessage]],
            "max_tokens": 8192,
        ]

        let data = try await postJSON(
            path: "/api/v1/stories/generate",
            body: body,
            token: token
        )

        // The backend returns the Anthropic response + _usage metadata
        let response = try JSONDecoder().decode(AnthropicProxyResponse.self, from: data)

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

        return try JSONDecoder().decode(NarrativeResult.self, from: jsonData)
    }

    // MARK: - Single Story

    func generateSingleStory(systemPrompt: String, userMessage: String) async throws -> StoryResponse {
        let token = try await requireToken()

        let body: [String: Any] = [
            "systemPrompt": systemPrompt,
            "messages": [["role": "user", "content": userMessage]],
            "max_tokens": 1024,
        ]

        let data = try await postJSON(
            path: "/api/v1/stories/single",
            body: body,
            token: token
        )

        let response = try JSONDecoder().decode(AnthropicProxyResponse.self, from: data)

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

    // MARK: - Streaming Chat (via Lambda Function URL)

    func streamChat(messages: [[String: String]], systemPrompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let token = try await self.requireToken()

                    let body: [String: Any] = [
                        "messages": messages,
                        "systemPrompt": systemPrompt,
                        "max_tokens": 1024,
                    ]

                    var request = URLRequest(url: URL(string: BackendConfig.chatStreamURL)!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMError.httpError(-1)
                    }

                    if httpResponse.statusCode == 429 {
                        throw LLMError.rateLimited
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw LLMError.httpError(httpResponse.statusCode)
                    }

                    // Parse SSE stream — same format as direct Anthropic
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

    // MARK: - Usage

    /// Fetch current usage quotas from the backend.
    func fetchUsage() async throws -> UsageInfo {
        let token = try await requireToken()
        let data = try await getJSON(path: "/api/v1/usage", token: token)
        return try JSONDecoder().decode(UsageInfo.self, from: data)
    }

    // MARK: - Account Deletion

    /// Request account deletion via DELETE /api/v1/account.
    func deleteAccount() async throws {
        let token = try await requireToken()
        let url = URL(string: BackendConfig.apiBaseURL + "/api/v1/account")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.httpError(-1)
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw LLMError.httpError(httpResponse.statusCode, errorBody)
        }
    }

    // MARK: - Helpers

    @MainActor
    private func requireToken() async throws -> String {
        guard let token = await authService.currentToken else {
            throw AuthError.noToken
        }
        return token
    }

    private func postJSON(path: String, body: [String: Any], token: String) async throws -> Data {
        let url = URL(string: BackendConfig.apiBaseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.httpError(-1)
        }

        if httpResponse.statusCode == 429 {
            throw LLMError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw LLMError.httpError(httpResponse.statusCode, errorBody)
        }

        return data
    }

    private func getJSON(path: String, token: String) async throws -> Data {
        let url = URL(string: BackendConfig.apiBaseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LLMError.httpError(statusCode)
        }

        return data
    }
}

// MARK: - Response Models

/// Anthropic response proxied through our backend (includes original fields + _usage).
private struct AnthropicProxyResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}

/// SSE streaming event from Anthropic (same format through our proxy).
private struct StreamEvent: Decodable {
    let type: String
    let delta: Delta?

    struct Delta: Decodable {
        let type: String?
        let text: String?
    }
}

/// Usage info from GET /api/v1/usage.
struct UsageInfo: Codable {
    let stories: ResourceUsage
    let chats: ResourceUsage
    let resetsAt: String

    struct ResourceUsage: Codable {
        let used: Int
        let limit: Int

        var remaining: Int { limit - used }
        var isAtLimit: Bool { used >= limit }
    }
}
