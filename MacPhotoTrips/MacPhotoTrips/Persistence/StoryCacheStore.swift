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
