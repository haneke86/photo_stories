import Foundation
import CryptoKit

/// File-based catalog for individual story cards.
/// Directory: Documents/story_catalog/, one JSON file per card.
actor StoryCatalog {
    private let catalogDir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        catalogDir = docs.appendingPathComponent("story_catalog")
        try? FileManager.default.createDirectory(at: catalogDir, withIntermediateDirectories: true)
    }

    /// Load all cached story cards.
    func loadAll() -> [StoryCard] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: catalogDir, includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(StoryCard.self, from: data)
            }
    }

    /// Save a single story card.
    func save(_ card: StoryCard) {
        let url = catalogDir.appendingPathComponent("\(card.id).json")
        guard let data = try? JSONEncoder().encode(card) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Check if a story is cached with the current timeline hash.
    func isCached(id: String, hash: String) -> Bool {
        let url = catalogDir.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url),
              let card = try? JSONDecoder().decode(StoryCard.self, from: data) else {
            return false
        }
        return card.timelineHash == hash
    }

    /// Remove cards whose timelineHash doesn't match the current one.
    func invalidateStale(currentHash: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: catalogDir, includingPropertiesForKeys: nil
        ) else { return }

        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let card = try? JSONDecoder().decode(StoryCard.self, from: data) else {
                continue
            }
            if card.timelineHash != currentHash {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Compute SHA256 hash of a timeline for cache invalidation.
    static func hash(for timeline: Timeline) -> String {
        let compact: [String: Any] = [
            "trips": timeline.trips.map { ["id": $0.id, "cities": $0.cities] as [String: Any] },
            "years": timeline.years.map { ["year": $0.year, "trips": $0.trips] as [String: Any] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: compact, options: .sortedKeys) else {
            return UUID().uuidString
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
