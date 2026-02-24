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
