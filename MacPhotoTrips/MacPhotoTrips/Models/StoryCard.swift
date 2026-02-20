import Foundation

/// A single story card in the feed — persisted to Documents/story_catalog/.
struct StoryCard: Codable, Identifiable {

    /// Deterministic ID: "trip-{id}", "year-2024", "season-summer-2024", "location-Istanbul-Türkiye"
    let id: String

    let type: StoryType

    // LLM-generated content
    let title: String
    let tagline: String
    let narrative: String

    let generatedAt: Date

    // Display metadata
    let flags: [String]       // emoji flags
    let countries: [String]
    let dateLabel: String
    let durationLabel: String?
    let associatedTripIds: [String]

    /// SHA256 of the timeline data used to generate — for cache invalidation.
    let timelineHash: String
}

enum StoryType: String, Codable {
    case trip
    case yearInReview = "year_in_review"
    case season
    case locationSpotlight = "location_spotlight"

    var label: String {
        switch self {
        case .trip: return "Trip"
        case .yearInReview: return "Year in Review"
        case .season: return "Season"
        case .locationSpotlight: return "Location"
        }
    }

    var icon: String {
        switch self {
        case .trip: return "airplane"
        case .yearInReview: return "calendar"
        case .season: return "leaf"
        case .locationSpotlight: return "mappin.circle"
        }
    }
}
