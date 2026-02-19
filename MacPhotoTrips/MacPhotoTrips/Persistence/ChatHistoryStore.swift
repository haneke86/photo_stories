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
