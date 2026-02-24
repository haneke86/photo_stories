import SwiftUI
import MapKit

/// Transforms Timeline data into view-ready structures for the dashboard.
@MainActor
final class DashboardViewModel: ObservableObject {

    var timeline: Timeline

    init(timeline: Timeline) {
        self.timeline = timeline
    }

    // MARK: - Timeline Updates

    /// Replace the timeline with refined data, preserving any loaded narratives.
    func updateTimeline(_ newTimeline: Timeline) {
        // Collect existing narratives before replacing
        let oldTripNarratives = Dictionary(
            uniqueKeysWithValues: timeline.trips.compactMap { trip -> (String, (String?, String?))? in
                guard trip.narrative != nil || trip.tagline != nil else { return nil }
                return (trip.id, (trip.narrative, trip.tagline))
            }
        )
        let oldYearNarratives = Dictionary(
            uniqueKeysWithValues: timeline.years.compactMap { year -> (Int, String?)? in
                guard year.narrative != nil else { return nil }
                return (year.year, year.narrative)
            }
        )

        timeline = newTimeline

        // Re-apply narratives to the new timeline
        if narrativesLoaded {
            for i in timeline.trips.indices {
                if let (narrative, tagline) = oldTripNarratives[timeline.trips[i].id] {
                    timeline.trips[i].narrative = narrative
                    timeline.trips[i].tagline = tagline
                }
            }
            for i in timeline.years.indices {
                if let narrative = oldYearNarratives[timeline.years[i].year] {
                    timeline.years[i].narrative = narrative
                }
            }
        }

        objectWillChange.send()
    }

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

    /// Set narrative + tagline for a single trip (from on-demand generation).
    func setTripNarrative(tripId: String, narrative: String, tagline: String) {
        guard let i = timeline.trips.firstIndex(where: { $0.id == tripId }) else { return }
        timeline.trips[i].narrative = narrative
        timeline.trips[i].tagline = tagline
        objectWillChange.send()
    }

    // MARK: - Hero

    var countriesCount: Int { timeline.summary.countriesVisited }
    var sinceYear: String { String(timeline.dateRange.from.prefix(4)) }
    var homeCity: String { timeline.homeBase.city }
    var totalTrips: Int { timeline.summary.totalTrips }
    var totalDays: Int { timeline.summary.totalDaysTraveling }

    // MARK: - Year Groups

    struct YearGroup: Identifiable {
        let year: Int
        let trips: [Trip]
        let yearNarrative: String?
        var id: Int { year }
    }

    var yearGroups: [YearGroup] {
        let tripLookup = Dictionary(uniqueKeysWithValues: timeline.trips.map { ($0.id, $0) })

        return timeline.years.compactMap { yearSummary in
            let trips = yearSummary.trips.compactMap { tripLookup[$0] }
            guard !trips.isEmpty else { return nil }
            return YearGroup(year: yearSummary.year, trips: trips, yearNarrative: yearSummary.narrative)
        }.sorted { $0.year > $1.year }  // newest first
    }

    // MARK: - Trip Display Helpers

    func tripLabel(_ trip: Trip) -> String {
        if trip.cities.count == 1 {
            return trip.cities[0]
        }
        return trip.cities.prefix(3).joined(separator: " → ")
    }

    func tripFlag(_ trip: Trip) -> String {
        guard let firstCountry = trip.countries.first else { return "" }
        return CountryFlags.flag(forCountry: firstCountry)
    }

    func tripDateRange(_ trip: Trip) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        guard let dep = formatter.date(from: trip.departureDate),
              let ret = formatter.date(from: trip.returnDate) else {
            return trip.departureDate
        }

        let display = DateFormatter()
        display.dateFormat = "MMM d"
        let yearFmt = DateFormatter()
        yearFmt.dateFormat = "MMM d, yyyy"

        if Calendar.current.component(.year, from: dep) == Calendar.current.component(.year, from: ret) {
            return "\(display.string(from: dep)) – \(display.string(from: ret))"
        }
        return "\(yearFmt.string(from: dep)) – \(yearFmt.string(from: ret))"
    }

    // MARK: - Map Annotations

    struct StopAnnotation: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let city: String
        let country: String
        let days: Int
        let tripId: String
    }

    var allStopAnnotations: [StopAnnotation] {
        timeline.trips.flatMap { trip in
            trip.stops.map { stop in
                StopAnnotation(
                    id: "\(trip.id)-\(stop.city)",
                    coordinate: CLLocationCoordinate2D(
                        latitude: stop.coordinates.lat,
                        longitude: stop.coordinates.lon
                    ),
                    city: stop.city,
                    country: stop.country,
                    days: stop.days,
                    tripId: trip.id
                )
            }
        }
    }

    /// Look up a trip by its ID.
    func trip(byId id: String) -> Trip? {
        timeline.trips.first { $0.id == id }
    }

    // MARK: - Stats Tab Data

    var totalCities: Int { timeline.summary.citiesVisited }
    var totalPhotos: Int { timeline.trips.reduce(0) { $0 + $1.photoCount } }

    var averageTripDuration: Double {
        guard !timeline.trips.isEmpty else { return 0 }
        return Double(totalDays) / Double(timeline.trips.count)
    }

    /// Top countries sorted by number of trips (descending).
    var countryFrequency: [(country: String, count: Int)] {
        var freq: [String: Int] = [:]
        for trip in timeline.trips {
            for country in trip.countries {
                freq[country, default: 0] += 1
            }
        }
        return freq.map { (country: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    var longestTrip: Trip? {
        timeline.trips.max(by: { $0.durationDays < $1.durationDays })
    }

    var mostVisitedCountry: String? {
        countryFrequency.first?.country
    }

    var busiestYear: YearSummary? {
        timeline.years.max(by: { $0.tripsCount < $1.tripsCount })
    }

    /// Trips per year, sorted chronologically.
    var tripsPerYear: [(year: Int, count: Int)] {
        timeline.years.map { (year: $0.year, count: $0.tripsCount) }
            .sorted { $0.year < $1.year }
    }

    /// Days abroad per year, sorted chronologically.
    var daysPerYear: [(year: Int, days: Int)] {
        timeline.years.map { (year: $0.year, days: $0.daysAbroad) }
            .sorted { $0.year < $1.year }
    }

    /// New countries discovered per year, sorted chronologically.
    var newCountriesPerYear: [(year: Int, count: Int)] {
        timeline.years.map { (year: $0.year, count: $0.newCountries.count) }
            .sorted { $0.year < $1.year }
    }

    // MARK: - Travel Records

    /// Trip with the farthest stop from home base (great-circle distance).
    var farthestTrip: (trip: Trip, distanceKm: Double, city: String)? {
        let home = timeline.homeBase
        var best: (trip: Trip, distanceKm: Double, city: String)?

        for trip in timeline.trips {
            for stop in trip.stops {
                let dist = Haversine.distanceKm(
                    lat1: home.center.lat, lon1: home.center.lon,
                    lat2: stop.coordinates.lat, lon2: stop.coordinates.lon
                )
                if dist > (best?.distanceKm ?? 0) {
                    best = (trip: trip, distanceKm: dist, city: stop.city)
                }
            }
        }
        return best
    }

    /// Trip with the most unique cities visited. Only returned if cityCount > 1.
    var mostCitiesTrip: (trip: Trip, cityCount: Int)? {
        guard let trip = timeline.trips.max(by: { $0.cities.count < $1.cities.count }),
              trip.cities.count > 1 else { return nil }
        return (trip: trip, cityCount: trip.cities.count)
    }

    /// Longest gap (in days) between consecutive trips.
    var longestHomeStretch: (days: Int, afterTrip: String, beforeTrip: String)? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let sorted = timeline.trips.sorted {
            (formatter.date(from: $0.departureDate) ?? .distantPast)
                < (formatter.date(from: $1.departureDate) ?? .distantPast)
        }

        guard sorted.count >= 2 else { return nil }

        var best: (days: Int, afterTrip: String, beforeTrip: String)?

        for i in 0..<(sorted.count - 1) {
            guard let returnDate = formatter.date(from: sorted[i].returnDate),
                  let nextDeparture = formatter.date(from: sorted[i + 1].departureDate) else { continue }

            let gap = Calendar.current.dateComponents([.day], from: returnDate, to: nextDeparture).day ?? 0
            if gap > (best?.days ?? 0) {
                let afterLabel = sorted[i].cities.first ?? sorted[i].id
                let beforeLabel = sorted[i + 1].cities.first ?? sorted[i + 1].id
                best = (days: gap, afterTrip: afterLabel, beforeTrip: beforeLabel)
            }
        }
        return best
    }

    /// Calendar month with the most trip departures. Only returned if count > 1.
    var busiestMonth: (month: String, year: Int, tripCount: Int)? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var freq: [String: (month: Int, year: Int, count: Int)] = [:]

        for trip in timeline.trips {
            guard let date = formatter.date(from: trip.departureDate) else { continue }
            let cal = Calendar.current
            let month = cal.component(.month, from: date)
            let year = cal.component(.year, from: date)
            let key = "\(year)-\(month)"
            if let existing = freq[key] {
                freq[key] = (month: month, year: year, count: existing.count + 1)
            } else {
                freq[key] = (month: month, year: year, count: 1)
            }
        }

        guard let top = freq.values.max(by: { $0.count < $1.count }),
              top.count > 1 else { return nil }

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        var comps = DateComponents()
        comps.month = top.month
        let monthName = Calendar.current.date(from: comps).map { monthFormatter.string(from: $0) } ?? "Unknown"

        return (month: monthName, year: top.year, tripCount: top.count)
    }

    /// Trip with the highest photo count.
    var mostPhotogenicTrip: Trip? {
        timeline.trips.max(by: { $0.photoCount < $1.photoCount })
    }

    // MARK: - Timeline Bar Data

    struct TimelineBlock: Identifiable {
        let id: String
        let startPercent: Double  // 0-100
        let widthPercent: Double  // 0-100
        let label: String
        let duration: Int
    }

    struct TimelineYear: Identifiable {
        let year: Int
        let blocks: [TimelineBlock]
        var id: Int { year }
    }

    var timelineYears: [TimelineYear] {
        let tripLookup = Dictionary(uniqueKeysWithValues: timeline.trips.map { ($0.id, $0) })
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        return timeline.years.map { yearSummary in
            let blocks = yearSummary.trips.compactMap { tripId -> TimelineBlock? in
                guard let trip = tripLookup[tripId],
                      let dep = formatter.date(from: trip.departureDate),
                      let ret = formatter.date(from: trip.returnDate) else { return nil }

                let cal = Calendar.current
                let dayOfYear = cal.ordinality(of: .day, in: .year, for: dep) ?? 1
                let daysInYear = cal.range(of: .day, in: .year, for: dep)?.count ?? 365

                let startPct = Double(dayOfYear - 1) / Double(daysInYear) * 100
                let widthPct = max(1, Double(trip.durationDays) / Double(daysInYear) * 100)

                return TimelineBlock(
                    id: trip.id,
                    startPercent: startPct,
                    widthPercent: widthPct,
                    label: trip.cities.first ?? "Trip",
                    duration: trip.durationDays
                )
            }
            return TimelineYear(year: yearSummary.year, blocks: blocks)
        }
    }
}
