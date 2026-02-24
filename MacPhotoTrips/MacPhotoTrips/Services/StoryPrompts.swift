import Foundation

/// A prompt ready for the LLM — one per story card.
struct StoryPrompt {
    let storyId: String
    let type: StoryType
    let systemPrompt: String
    let userMessage: String
    let associatedTripIds: [String]

    // Pre-computed display context (flags, countries, date, duration)
    let flags: [String]
    let countries: [String]
    let dateLabel: String
    let durationLabel: String?
}

/// Builds all story prompts from a timeline, grouped by type.
enum StoryPromptBuilder {

    /// Build prompts for all story types, newest first within each type.
    static func buildAll(from timeline: Timeline) -> [StoryPrompt] {
        var prompts: [StoryPrompt] = []
        prompts.append(contentsOf: tripPrompts(from: timeline))
        prompts.append(contentsOf: yearPrompts(from: timeline))
        prompts.append(contentsOf: seasonPrompts(from: timeline))
        prompts.append(contentsOf: locationPrompts(from: timeline))
        return prompts
    }

    // MARK: - Trip Prompts

    private static func tripPrompts(from timeline: Timeline) -> [StoryPrompt] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let display = DateFormatter()
        display.dateFormat = "MMM d, yyyy"

        return timeline.trips
            .sorted { $0.departureDate > $1.departureDate }
            .map { trip in
                let depDate = formatter.date(from: trip.departureDate)
                let retDate = formatter.date(from: trip.returnDate)
                let dateLabel: String = {
                    guard let d = depDate, let r = retDate else { return trip.departureDate }
                    return "\(display.string(from: d)) – \(display.string(from: r))"
                }()

                let cityRoute = trip.cities.joined(separator: " → ")
                let stopDetails = trip.stops.map { "\($0.city) (\($0.days)d)" }.joined(separator: ", ")

                let userMsg = """
                Write a story about this trip:
                - Route: \(cityRoute)
                - Countries: \(trip.countries.joined(separator: ", "))
                - Duration: \(trip.durationDays) days
                - Dates: \(trip.departureDate) to \(trip.returnDate)
                - Stops: \(stopDetails)
                """

                return StoryPrompt(
                    storyId: "trip-\(trip.id)",
                    type: .trip,
                    systemPrompt: Self.tripSystemPrompt,
                    userMessage: userMsg,
                    associatedTripIds: [trip.id],
                    flags: trip.countries.map { CountryFlags.flag(forCountry: $0) },
                    countries: trip.countries,
                    dateLabel: dateLabel,
                    durationLabel: "\(trip.durationDays) days"
                )
            }
    }

    // MARK: - Year Prompts

    private static func yearPrompts(from timeline: Timeline) -> [StoryPrompt] {
        let tripLookup = Dictionary(uniqueKeysWithValues: timeline.trips.map { ($0.id, $0) })

        return timeline.years
            .sorted { $0.year > $1.year }
            .map { year in
                let trips = year.trips.compactMap { tripLookup[$0] }
                let destinations = trips.flatMap(\.cities).uniqued()
                let countries = year.countries

                let tripSummaries = trips.map { trip in
                    "\(trip.cities.joined(separator: "→")) (\(trip.durationDays)d, \(trip.departureDate))"
                }.joined(separator: "; ")

                let userMsg = """
                Write a year-in-review story for \(year.year):
                - Trips: \(year.tripsCount)
                - Days abroad: \(year.daysAbroad)
                - Countries: \(countries.joined(separator: ", "))
                - New countries: \(year.newCountries.joined(separator: ", "))
                - Destinations: \(destinations.joined(separator: ", "))
                - Trip details: \(tripSummaries)
                """

                let allFlags = countries.map { CountryFlags.flag(forCountry: $0) }

                return StoryPrompt(
                    storyId: "year-\(year.year)",
                    type: .yearInReview,
                    systemPrompt: Self.yearSystemPrompt,
                    userMessage: userMsg,
                    associatedTripIds: year.trips,
                    flags: allFlags,
                    countries: countries,
                    dateLabel: "\(year.year)",
                    durationLabel: "\(year.daysAbroad) days abroad"
                )
            }
    }

    // MARK: - Season Prompts

    private static func seasonPrompts(from timeline: Timeline) -> [StoryPrompt] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        // Group trips by season+year
        var seasonBuckets: [String: [(trip: Trip, season: String, year: Int)]] = [:]

        for trip in timeline.trips {
            guard let date = formatter.date(from: trip.departureDate) else { continue }
            let month = Calendar.current.component(.month, from: date)
            let year = Calendar.current.component(.year, from: date)
            let season = Self.season(for: month)
            let key = "\(season)-\(year)"
            seasonBuckets[key, default: []].append((trip, season, year))
        }

        return seasonBuckets
            .filter { $0.value.count >= 2 }  // Only if 2+ trips in season
            .sorted { $0.key > $1.key }
            .map { key, entries in
                let season = entries[0].season
                let year = entries[0].year
                let trips = entries.map(\.trip)
                let allCountries = trips.flatMap(\.countries).uniqued()
                let allCities = trips.flatMap(\.cities).uniqued()
                let totalDays = trips.reduce(0) { $0 + $1.durationDays }

                let userMsg = """
                Write a seasonal mood story for \(season.capitalized) \(year):
                - Trips: \(trips.count)
                - Total days: \(totalDays)
                - Cities: \(allCities.joined(separator: ", "))
                - Countries: \(allCountries.joined(separator: ", "))
                """

                return StoryPrompt(
                    storyId: "season-\(season)-\(year)",
                    type: .season,
                    systemPrompt: Self.seasonSystemPrompt,
                    userMessage: userMsg,
                    associatedTripIds: trips.map(\.id),
                    flags: allCountries.map { CountryFlags.flag(forCountry: $0) },
                    countries: allCountries,
                    dateLabel: "\(season.capitalized) \(year)",
                    durationLabel: "\(totalDays) days"
                )
            }
    }

    // MARK: - Location Prompts

    private static func locationPrompts(from timeline: Timeline) -> [StoryPrompt] {
        // Group trips by city+country
        struct CityKey: Hashable { let city: String; let country: String }
        var cityVisits: [CityKey: [Trip]] = [:]

        for trip in timeline.trips {
            for stop in trip.stops {
                let key = CityKey(city: stop.city, country: stop.country)
                if cityVisits[key]?.contains(where: { $0.id == trip.id }) != true {
                    cityVisits[key, default: []].append(trip)
                }
            }
        }

        return cityVisits
            .filter { $0.value.count >= 2 }  // Only cities with 2+ visits
            .sorted { $0.value.count > $1.value.count }
            .map { key, trips in
                let visitDates = trips.map(\.departureDate).sorted()
                let totalVisits = trips.count

                let userMsg = """
                Write a location spotlight story about \(key.city), \(key.country):
                - Total visits: \(totalVisits)
                - Visit dates: \(visitDates.joined(separator: ", "))
                - Trips involving this city: \(trips.map { $0.cities.joined(separator: "→") }.joined(separator: "; "))
                """

                return StoryPrompt(
                    storyId: "location-\(key.city)-\(key.country)",
                    type: .locationSpotlight,
                    systemPrompt: Self.locationSystemPrompt,
                    userMessage: userMsg,
                    associatedTripIds: trips.map(\.id),
                    flags: [CountryFlags.flag(forCountry: key.country)],
                    countries: [key.country],
                    dateLabel: "\(totalVisits) visits",
                    durationLabel: nil
                )
            }
    }

    // MARK: - Helpers

    private static func season(for month: Int) -> String {
        switch month {
        case 3...5: return "spring"
        case 6...8: return "summer"
        case 9...11: return "fall"
        default: return "winter"
        }
    }

    // MARK: - System Prompts

    private static let baseRules = """
    STYLE:
    - Write in second person ("You spent...", "You explored...")
    - Be warm but concise — no fluff or filler
    - Reference specific cities, seasons, and durations
    - Keep the tone personal and reflective, like a travel journal

    IMPORTANT: Respond with ONLY valid JSON matching:
    {"title": "...", "tagline": "...", "narrative": "..."}

    - title: 3-6 words, evocative heading
    - tagline: 5-8 words, poetic one-liner
    - narrative: 2-4 sentences capturing the essence
    """

    static let tripSystemPrompt = """
    You are a travel storyteller writing about a single trip.
    \(baseRules)
    Focus on the journey between stops, the mood, and what makes this trip unique.
    """

    static let yearSystemPrompt = """
    You are a travel storyteller summarizing a year of travel.
    \(baseRules)
    Highlight the year's travel pattern — was it restless exploration or deep immersion?
    Mention standout trips and new countries discovered.
    """

    static let seasonSystemPrompt = """
    You are a travel storyteller capturing the mood of a season.
    \(baseRules)
    Evoke the season's atmosphere — summer warmth, winter escapes, spring awakening, autumn colors.
    """

    static let locationSystemPrompt = """
    You are a travel storyteller writing about someone's relationship with a place.
    \(baseRules)
    Explore why this person keeps returning. What draws them back?
    """
}

// MARK: - Array Extension

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
