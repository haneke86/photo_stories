import SwiftUI
import MapKit

/// Transforms Timeline data into view-ready structures for the dashboard.
@MainActor
final class DashboardViewModel: ObservableObject {

    var timeline: Timeline

    init(timeline: Timeline) {
        self.timeline = timeline
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
                    days: stop.days
                )
            }
        }
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
