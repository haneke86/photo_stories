import Foundation

/// Save/load timeline.json to/from the app's Documents directory.
enum TimelineStore {

    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private static var timelineURL: URL {
        documentsURL.appendingPathComponent("timeline.json")
    }

    /// Save timeline to Documents/timeline.json.
    static func save(_ timeline: Timeline) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(timeline)
        try data.write(to: timelineURL, options: .atomic)
    }

    /// Load timeline from Documents/timeline.json, if it exists.
    static func load() -> Timeline? {
        guard FileManager.default.fileExists(atPath: timelineURL.path) else { return nil }
        guard let data = try? Data(contentsOf: timelineURL) else { return nil }
        return try? JSONDecoder().decode(Timeline.self, from: data)
    }

    /// URL for sharing the timeline.json file.
    static func shareURL() -> URL? {
        FileManager.default.fileExists(atPath: timelineURL.path) ? timelineURL : nil
    }

    /// Delete saved timeline.
    static func delete() throws {
        if FileManager.default.fileExists(atPath: timelineURL.path) {
            try FileManager.default.removeItem(at: timelineURL)
        }
    }
}
