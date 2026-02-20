import Foundation

/// Assembles the complete Timeline from detected trips.
/// Port of trips.py:276-315 (build_timeline) and :231-273 (build_year_summaries).
enum TimelineBuilder {

    /// Main entry point: build the complete Timeline from photo records.
    /// Port of trips.py:276-315 (build_timeline).
    static func build(from records: [PhotoRecord]) -> Timeline {
        let homeBase = HomeDetector.detect(from: records)
        let trips = TripDetector.detect(from: records, homeBase: homeBase)
        let yearSummaries = buildYearSummaries(trips: trips)

        // All-time stats
        let totalDays = trips.reduce(0) { $0 + $1.durationDays }
        var tripCountries: Set<String> = []
        var tripCities: Set<String> = []
        for trip in trips {
            tripCountries.formUnion(trip.countries)
            tripCities.formUnion(trip.cities)
        }

        // Date range
        let dates = records.map(\.date)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let fromDate = dates.min().map { dateFormatter.string(from: $0) } ?? ""
        let toDate = dates.max().map { dateFormatter.string(from: $0) } ?? ""

        return Timeline(
            homeBase: homeBase,
            dateRange: DateRange(from: fromDate, to: toDate),
            summary: Summary(
                totalTrips: trips.count,
                countriesVisited: tripCountries.count,
                citiesVisited: tripCities.count,
                totalDaysTraveling: totalDays
            ),
            years: yearSummaries,
            trips: trips
        )
    }

    /// Build per-year summary dicts. Tracks new countries (first time visited in any year).
    /// Port of trips.py:231-273 (build_year_summaries).
    static func buildYearSummaries(trips: [Trip]) -> [YearSummary] {
        let sorted = trips.sorted { $0.departureDate < $1.departureDate }
        var seenCountries: Set<String> = []
        var yearData: [Int: YearAccumulator] = [:]

        for trip in sorted {
            guard let year = Int(trip.departureDate.prefix(4)) else { continue }
            var acc = yearData[year] ?? YearAccumulator(year: year)

            acc.tripsCount += 1
            acc.daysAbroad += trip.durationDays
            acc.tripIds.append(trip.id)

            for country in trip.countries {
                if !acc.countries.contains(country) {
                    acc.countries.append(country)
                }
                if !seenCountries.contains(country) {
                    acc.newCountries.append(country)
                    seenCountries.insert(country)
                }
            }

            if acc.longestTripDays == nil || trip.durationDays > acc.longestTripDays! {
                let dest = trip.cities.count == 1 ? trip.cities[0] : "Multi-city"
                acc.longestTripDest = dest
                acc.longestTripDays = trip.durationDays
            }

            yearData[year] = acc
        }

        return yearData.keys.sorted().map { year in
            let acc = yearData[year]!
            return YearSummary(
                year: acc.year,
                tripsCount: acc.tripsCount,
                countries: acc.countries,
                newCountries: acc.newCountries,
                daysAbroad: acc.daysAbroad,
                longestTrip: acc.longestTripDays.map {
                    LongestTrip(destination: acc.longestTripDest ?? "Unknown", days: $0)
                },
                trips: acc.tripIds
            )
        }
    }
}

/// Working accumulator for year summaries.
private struct YearAccumulator {
    let year: Int
    var tripsCount = 0
    var countries: [String] = []
    var newCountries: [String] = []
    var daysAbroad = 0
    var longestTripDest: String?
    var longestTripDays: Int?
    var tripIds: [String] = []
}
