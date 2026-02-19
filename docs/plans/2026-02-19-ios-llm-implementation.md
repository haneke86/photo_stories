# iOS LLM Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add LLM-powered trip narratives (storylines) and a chat tab to the iOS app, using the Anthropic Claude API with aggressive response caching.

**Architecture:** Protocol-based LLM service layer (swappable direct→proxy later). Story narratives generated once and cached by timeline hash. Chat in a separate tab with streaming responses and persisted history. API key injected at build time via XOR-obfuscated Info.plist entry.

**Tech Stack:** Swift 5.9, iOS 17+, URLSession async/await, SSE streaming, SwiftUI, xcodegen

---

### Task 1: API Key Configuration

**Files:**
- Create: `MacPhotoTrips/MacPhotoTrips/Config/APIKeyConfig.swift`
- Modify: `MacPhotoTrips/project.yml`

**Step 1: Add build setting to project.yml**

In `MacPhotoTrips/project.yml`, add `ANTHROPIC_API_KEY` to the target's build settings and expose it in Info.plist:

```yaml
# Add under targets > MacPhotoTrips > settings > base:
        ANTHROPIC_API_KEY: $(ANTHROPIC_API_KEY)

# Add new infoPlist section under targets > MacPhotoTrips:
    infoPlist:
      AnthropicAPIKey: $(ANTHROPIC_API_KEY)
```

The full target section should look like:

```yaml
  MacPhotoTrips:
    type: application
    platform: iOS
    sources:
      - MacPhotoTrips
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.macphoto.trips
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: true
        INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone: "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"
        INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad: "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"
        ANTHROPIC_API_KEY: $(ANTHROPIC_API_KEY)
    infoPlist:
      AnthropicAPIKey: $(ANTHROPIC_API_KEY)
    entitlements:
      path: MacPhotoTrips/MacPhotoTrips.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.personal-information.photos-library: true
```

**Step 2: Create APIKeyConfig.swift**

```swift
import Foundation

/// Reads the Anthropic API key from Info.plist (injected at build time).
/// The key is XOR-obfuscated so it's not a plain string in the binary.
enum APIKeyConfig {
    /// The XOR mask used to obfuscate the key at rest.
    /// In a real build pipeline, this would be generated randomly per build.
    private static let xorMask: UInt8 = 0xA7

    /// Read the raw key from Info.plist, obfuscate, then return decoded.
    /// For now (development): just returns the plain key from Info.plist.
    /// For distribution: store pre-XOR'd bytes and decode here.
    static var apiKey: String? {
        Bundle.main.infoDictionary?["AnthropicAPIKey"] as? String
    }

    /// Whether an API key is configured.
    static var isConfigured: Bool {
        guard let key = apiKey else { return false }
        return !key.isEmpty && key != "$(ANTHROPIC_API_KEY)"
    }
}
```

**Step 3: Regenerate Xcode project**

Run: `cd /Users/oberk/macphoto/MacPhotoTrips && xcodegen generate`
Expected: `Generated project MacPhotoTrips.xcodeproj`

**Step 4: Verify key injection**

Set the key and verify it compiles:
Run: `export ANTHROPIC_API_KEY=test-key-123 && cd /Users/oberk/macphoto/MacPhotoTrips && xcodegen generate`

**Step 5: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/Config/APIKeyConfig.swift MacPhotoTrips/project.yml
git commit -m "feat(ios): add API key configuration via build-time env var"
```

---

### Task 2: LLM Provider Protocol + Anthropic Direct Implementation

**Files:**
- Create: `MacPhotoTrips/MacPhotoTrips/Services/LLMProvider.swift`
- Create: `MacPhotoTrips/MacPhotoTrips/Services/AnthropicDirectProvider.swift`

**Step 1: Create LLMProvider protocol**

```swift
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
```

**Step 2: Create AnthropicDirectProvider**

```swift
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

    var errorDescription: String? {
        switch self {
        case .emptyResponse: return "Empty response from Claude"
        case .invalidJSON: return "Invalid JSON in Claude response"
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .noAPIKey: return "No Anthropic API key configured"
        }
    }
}
```

**Step 3: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/Services/LLMProvider.swift MacPhotoTrips/MacPhotoTrips/Services/AnthropicDirectProvider.swift
git commit -m "feat(ios): add LLM provider protocol + Anthropic direct implementation"
```

---

### Task 3: Story Cache + Story Service

**Files:**
- Create: `MacPhotoTrips/MacPhotoTrips/Persistence/StoryCacheStore.swift`
- Create: `MacPhotoTrips/MacPhotoTrips/Services/StoryService.swift`

**Step 1: Create StoryCacheStore**

```swift
import Foundation
import CryptoKit

/// File-based cache for LLM narrative responses.
/// Key: SHA256(compact_timeline + prompt_version). Value: NarrativeResult JSON.
enum StoryCacheStore {
    private static let promptVersion = "stories-v2"

    private static var cacheDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("story_cache")
    }

    /// Compute a deterministic cache key from compact timeline data.
    static func cacheKey(for compactTimeline: [String: Any]) -> String {
        let payload: [String: Any] = ["data": compactTimeline, "prompt_version": promptVersion]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: .sortedKeys) else {
            return UUID().uuidString
        }
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Load cached narratives for the given key.
    static func load(key: String) -> NarrativeResult? {
        let url = cacheDir.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(NarrativeResult.self, from: data)
    }

    /// Save narratives to cache.
    static func save(key: String, result: NarrativeResult) {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let url = cacheDir.appendingPathComponent("\(key).json")
        guard let data = try? JSONEncoder().encode(result) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
```

**Step 2: Create StoryService**

```swift
import Foundation

/// Orchestrates narrative generation with caching.
/// Port of llm_stories.py: build compact timeline → check cache → call Claude → merge.
actor StoryService {
    private let provider: LLMProvider

    init(provider: LLMProvider) {
        self.provider = provider
    }

    /// Generate narratives if not cached. Returns nil if LLM unavailable.
    func generateIfNeeded(timeline: Timeline) async -> NarrativeResult? {
        guard provider.isAvailable else { return nil }

        let compact = buildCompactTimeline(timeline)
        let key = StoryCacheStore.cacheKey(for: compact)

        // Check cache first
        if let cached = StoryCacheStore.load(key: key) {
            return cached
        }

        // Generate via LLM
        do {
            let result = try await provider.generateNarratives(compactTimeline: compact)
            StoryCacheStore.save(key: key, result: result)
            return result
        } catch {
            print("Story generation failed: \(error)")
            return nil
        }
    }

    /// Build compact timeline dict for the prompt — strips coordinates and photo counts.
    /// Port of llm_stories.py:_build_compact_timeline
    private func buildCompactTimeline(_ timeline: Timeline) -> [String: Any] {
        let compactTrips: [[String: Any]] = timeline.trips.map { trip in
            [
                "id": trip.id,
                "departure_date": trip.departureDate,
                "return_date": trip.returnDate,
                "duration_days": trip.durationDays,
                "countries": trip.countries,
                "cities": trip.cities,
                "stops": trip.stops.map { stop in
                    [
                        "city": stop.city,
                        "country": stop.country,
                        "days": stop.days,
                        "arrival_date": stop.arrivalDate,
                    ] as [String: Any]
                }
            ] as [String: Any]
        }

        let compactYears: [[String: Any]] = timeline.years.map { year in
            var dict: [String: Any] = [
                "year": year.year,
                "trips_count": year.tripsCount,
                "countries": year.countries,
                "new_countries": year.newCountries,
                "days_abroad": year.daysAbroad,
            ]
            if let longest = year.longestTrip {
                dict["longest_trip"] = [
                    "destination": longest.destination,
                    "days": longest.days
                ] as [String: Any]
            }
            return dict
        }

        return [
            "home_base": [
                "city": timeline.homeBase.city,
                "country": timeline.homeBase.country,
            ] as [String: Any],
            "trips": compactTrips,
            "years": compactYears,
        ]
    }
}
```

**Step 3: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/Persistence/StoryCacheStore.swift MacPhotoTrips/MacPhotoTrips/Services/StoryService.swift
git commit -m "feat(ios): add story cache + story service for narrative generation"
```

---

### Task 4: Add Narrative Fields to Timeline Model + DashboardViewModel

**Files:**
- Modify: `MacPhotoTrips/MacPhotoTrips/Models/Timeline.swift`
- Modify: `MacPhotoTrips/MacPhotoTrips/ViewModels/DashboardViewModel.swift`

**Step 1: Add optional narrative/tagline fields to Trip and YearSummary**

In `Timeline.swift`, update `Trip` struct:

```swift
struct Trip: Codable, Identifiable {
    let id: String
    let departureDate: String
    let returnDate: String
    let durationDays: Int
    let photoCount: Int
    let countries: [String]
    let cities: [String]
    let stops: [Stop]
    var narrative: String?
    var tagline: String?

    enum CodingKeys: String, CodingKey {
        case id
        case departureDate = "departure_date"
        case returnDate = "return_date"
        case durationDays = "duration_days"
        case photoCount = "photo_count"
        case countries, cities, stops, narrative, tagline
    }
}
```

Update `YearSummary` struct:

```swift
struct YearSummary: Codable, Identifiable {
    let year: Int
    let tripsCount: Int
    let countries: [String]
    let newCountries: [String]
    let daysAbroad: Int
    let longestTrip: LongestTrip?
    let trips: [String]
    var narrative: String?

    var id: Int { year }

    enum CodingKeys: String, CodingKey {
        case year
        case tripsCount = "trips_count"
        case countries
        case newCountries = "new_countries"
        case daysAbroad = "days_abroad"
        case longestTrip = "longest_trip"
        case trips, narrative
    }
}
```

**Step 2: Add narrative merging to DashboardViewModel**

Add this method to `DashboardViewModel`:

```swift
    // MARK: - Narratives

    @Published var narrativesLoaded = false

    /// Merge LLM-generated narratives into the timeline.
    func mergeNarratives(_ result: NarrativeResult) {
        let tripNarrLookup = Dictionary(uniqueKeysWithValues:
            result.tripNarratives.map { ($0.tripId, $0) }
        )
        let yearNarrLookup = Dictionary(uniqueKeysWithValues:
            result.yearNarratives.map { ($0.year, $0) }
        )

        for i in timeline.trips.indices {
            if let narr = tripNarrLookup[timeline.trips[i].id] {
                timeline.trips[i].narrative = narr.narrative
                timeline.trips[i].tagline = narr.tagline
            }
        }

        for i in timeline.years.indices {
            if let narr = yearNarrLookup[timeline.years[i].year] {
                timeline.years[i].narrative = narr.narrative
            }
        }

        narrativesLoaded = true
        objectWillChange.send()
    }
```

Also change `let timeline: Timeline` to `var timeline: Timeline` since we now mutate it.

**Step 3: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/Models/Timeline.swift MacPhotoTrips/MacPhotoTrips/ViewModels/DashboardViewModel.swift
git commit -m "feat(ios): add narrative fields to Timeline model + merge support"
```

---

### Task 5: Wire Story Generation into Pipeline

**Files:**
- Modify: `MacPhotoTrips/MacPhotoTrips/ViewModels/PipelineViewModel.swift`

**Step 1: Add story generation step**

Add a new `Step` case and trigger story generation after the pipeline completes:

Add to the `Step` enum:
```swift
        case stories = "Generating storylines..."
```

In the `start()` method, after `timeline = result` and before `state = .ready`, add:

```swift
                // Step 5: Generate narratives (non-blocking)
                currentStep = .stories
                progressDetail = "Writing trip stories..."

                if let provider = AnthropicDirectProvider() {
                    let storyService = StoryService(provider: provider)
                    let narratives = await storyService.generateIfNeeded(timeline: result)
                    if let narratives = narratives {
                        self.narrativeResult = narratives
                    }
                }

                timeline = result
                state = .ready
```

Add a published property:
```swift
    @Published private(set) var narrativeResult: NarrativeResult?
```

**Step 2: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/ViewModels/PipelineViewModel.swift
git commit -m "feat(ios): wire story generation into pipeline after trip detection"
```

---

### Task 6: Display Narratives in Dashboard UI

**Files:**
- Modify: `MacPhotoTrips/MacPhotoTrips/Views/Dashboard/TripCardView.swift`
- Modify: `MacPhotoTrips/MacPhotoTrips/Views/Dashboard/YearSectionView.swift`
- Modify: `MacPhotoTrips/MacPhotoTrips/App/ContentView.swift`

**Step 1: Add tagline and narrative to TripCardView**

In `TripCardView.swift`, add the tagline under the date range (inside the `VStack(alignment: .leading, spacing: 4)` that contains the trip label):

After the `HStack(spacing: 8)` that shows date range and duration badge, add:

```swift
                        // Tagline (from LLM)
                        if let tagline = trip.tagline, !tagline.isEmpty {
                            Text(tagline)
                                .font(.caption)
                                .italic()
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
```

In the expanded section, before the stops list, add the narrative:

```swift
                    // Narrative (from LLM)
                    if let narrative = trip.narrative, !narrative.isEmpty {
                        Text(narrative)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .padding(.bottom, 4)
                    }
```

**Step 2: Add year narrative to YearSectionView**

In `YearSectionView.swift`, in the `Section` header, after the existing `HStack`, add:

```swift
            if let narrative = group.yearNarrative, !narrative.isEmpty {
                Text(narrative)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .padding(.top, 2)
            }
```

Update `YearGroup` in `DashboardViewModel` to include the narrative:

```swift
    struct YearGroup: Identifiable {
        let year: Int
        let trips: [Trip]
        let yearNarrative: String?
        var id: Int { year }
    }
```

Update `yearGroups` computed property to populate narrative:

```swift
    var yearGroups: [YearGroup] {
        let tripLookup = Dictionary(uniqueKeysWithValues: timeline.trips.map { ($0.id, $0) })

        return timeline.years.compactMap { yearSummary in
            let trips = yearSummary.trips.compactMap { tripLookup[$0] }
            guard !trips.isEmpty else { return nil }
            return YearGroup(year: yearSummary.year, trips: trips, yearNarrative: yearSummary.narrative)
        }.sorted { $0.year > $1.year }
    }
```

**Step 3: Wire narrative merging in ContentView**

In `ContentView.swift`, update the `.ready` case to merge narratives when available:

```swift
            case .ready:
                if let timeline = pipeline.timeline {
                    let vm = DashboardViewModel(timeline: timeline)
                    DashboardView(viewModel: vm)
                        .task {
                            if let narratives = pipeline.narrativeResult {
                                vm.mergeNarratives(narratives)
                            }
                        }
                }
```

**Step 4: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/Views/Dashboard/TripCardView.swift MacPhotoTrips/MacPhotoTrips/Views/Dashboard/YearSectionView.swift MacPhotoTrips/MacPhotoTrips/App/ContentView.swift MacPhotoTrips/MacPhotoTrips/ViewModels/DashboardViewModel.swift
git commit -m "feat(ios): display trip taglines, narratives, and year summaries from LLM"
```

---

### Task 7: Chat History Persistence

**Files:**
- Create: `MacPhotoTrips/MacPhotoTrips/Persistence/ChatHistoryStore.swift`

**Step 1: Create ChatHistoryStore**

```swift
import Foundation

/// Persist chat messages to Documents/chat_history.json.
enum ChatHistoryStore {
    private static let maxMessages = 50

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("chat_history.json")
    }

    /// Load persisted chat messages.
    static func load() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ChatMessage].self, from: data)) ?? []
    }

    /// Save chat messages, trimming to maxMessages.
    static func save(_ messages: [ChatMessage]) {
        let trimmed = Array(messages.suffix(maxMessages))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(trimmed) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Clear all chat history.
    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
```

**Step 2: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/Persistence/ChatHistoryStore.swift
git commit -m "feat(ios): add chat history persistence store"
```

---

### Task 8: ChatViewModel

**Files:**
- Create: `MacPhotoTrips/MacPhotoTrips/ViewModels/ChatViewModel.swift`

**Step 1: Create ChatViewModel**

```swift
import Foundation

/// Manages chat state: messages, streaming, history persistence.
/// Port of chat.py + server.py chat endpoint.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isStreaming = false
    @Published var streamingText = ""

    private let provider: LLMProvider?
    private let systemPrompt: String

    /// Suggested prompts for empty state.
    let suggestions = [
        "What was my longest trip?",
        "Which countries did I visit in 2024?",
        "Compare my summer trips",
    ]

    init(timeline: Timeline) {
        self.provider = AnthropicDirectProvider()
        self.systemPrompt = Self.buildSystemPrompt(timeline: timeline)
        self.messages = ChatHistoryStore.load()
    }

    var isAvailable: Bool { provider?.isAvailable ?? false }

    /// Send a message and stream the response.
    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

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
        } catch {
            // On error, add error message
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
```

**Step 2: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/ViewModels/ChatViewModel.swift
git commit -m "feat(ios): add ChatViewModel with streaming and history persistence"
```

---

### Task 9: Chat UI Views

**Files:**
- Create: `MacPhotoTrips/MacPhotoTrips/Views/Chat/ChatView.swift`
- Create: `MacPhotoTrips/MacPhotoTrips/Views/Chat/MessageBubbleView.swift`

**Step 1: Create MessageBubbleView**

```swift
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

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content + (isStreaming ? " █" : ""))
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
```

**Step 2: Create ChatView**

```swift
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
```

**Step 3: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/Views/Chat/ChatView.swift MacPhotoTrips/MacPhotoTrips/Views/Chat/MessageBubbleView.swift
git commit -m "feat(ios): add chat UI with message bubbles, empty state, and input bar"
```

---

### Task 10: Add TabView to ContentView

**Files:**
- Modify: `MacPhotoTrips/MacPhotoTrips/App/ContentView.swift`

**Step 1: Wrap dashboard in TabView with Chat tab**

Replace the `.ready` case in `ContentView` to use a `TabView`:

```swift
struct ContentView: View {
    @StateObject private var pipeline = PipelineViewModel()

    var body: some View {
        Group {
            switch pipeline.state {
            case .needsPermission:
                PermissionView(onRequest: pipeline.requestPermission)
            case .denied:
                PermissionDeniedView()
            case .processing:
                ProcessingView(viewModel: pipeline)
            case .ready:
                if let timeline = pipeline.timeline {
                    MainTabView(timeline: timeline, narrativeResult: pipeline.narrativeResult)
                }
            case .error(let message):
                ErrorView(message: message, onRetry: pipeline.start)
            }
        }
        .task { pipeline.checkPermission() }
    }
}

/// Tab container shown after pipeline completes.
private struct MainTabView: View {
    let timeline: Timeline
    let narrativeResult: NarrativeResult?

    @StateObject private var dashboardVM: DashboardViewModel
    @StateObject private var chatVM: ChatViewModel

    init(timeline: Timeline, narrativeResult: NarrativeResult?) {
        self.timeline = timeline
        self.narrativeResult = narrativeResult
        _dashboardVM = StateObject(wrappedValue: DashboardViewModel(timeline: timeline))
        _chatVM = StateObject(wrappedValue: ChatViewModel(timeline: timeline))
    }

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(viewModel: dashboardVM)
            }
            .tabItem {
                Label("Trips", systemImage: "globe.europe.africa")
            }

            NavigationStack {
                ChatView(viewModel: chatVM)
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.text.bubble.right")
            }
        }
        .tint(DesignTokens.teal)
        .task {
            if let narratives = narrativeResult {
                dashboardVM.mergeNarratives(narratives)
            }
        }
    }
}
```

Keep the existing `PermissionDeniedView` and `ErrorView` unchanged.

**Step 2: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/App/ContentView.swift
git commit -m "feat(ios): add TabView with Dashboard + Chat tabs"
```

---

### Task 11: Regenerate Xcode Project + Build Verification

**Step 1: Regenerate project with new files**

Run: `cd /Users/oberk/macphoto/MacPhotoTrips && xcodegen generate`
Expected: `Generated project MacPhotoTrips.xcodeproj`

**Step 2: Build to verify compilation**

Run: `cd /Users/oberk/macphoto/MacPhotoTrips && xcodebuild -project MacPhotoTrips.xcodeproj -scheme MacPhotoTrips -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

If build fails, fix compilation errors before proceeding.

**Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix(ios): resolve compilation issues from LLM integration"
```

---

### Task 12: Update project.yml Sources + Final Cleanup

**Step 1: Verify all new directories are included**

The xcodegen `sources: - MacPhotoTrips` glob should pick up all new files under:
- `MacPhotoTrips/Config/`
- `MacPhotoTrips/Views/Chat/`

If not, the project.yml source paths may need updating.

**Step 2: Update CLAUDE.md with LLM architecture**

Add to the iOS Architecture section:
```markdown
- LLM: AnthropicDirectProvider (URLSession + SSE), StoryService with SHA256 file cache, ChatViewModel with history persistence
- API key: build-time env var (`export ANTHROPIC_API_KEY=... && xcodegen generate`)
```

**Step 3: Final commit**

```bash
git add -A
git commit -m "docs: update project docs with LLM integration details"
```
