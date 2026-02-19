import Foundation

/// Codable structs matching timeline.json schema exactly.
/// Uses explicit CodingKeys to produce snake_case JSON keys.
/// Must stay in sync with trips.py:299-313 output format.

struct Timeline: Codable {
    let homeBase: HomeBase
    let dateRange: DateRange
    let summary: Summary
    var years: [YearSummary]
    var trips: [Trip]

    enum CodingKeys: String, CodingKey {
        case homeBase = "home_base"
        case dateRange = "date_range"
        case summary, years, trips
    }
}

struct HomeBase: Codable {
    let city: String
    let country: String
    let center: Coordinate
    let radiusKm: Double

    enum CodingKeys: String, CodingKey {
        case city, country, center
        case radiusKm = "radius_km"
    }
}

struct Coordinate: Codable {
    let lat: Double
    let lon: Double
}

struct DateRange: Codable {
    let from: String
    let to: String
}

struct Summary: Codable {
    let totalTrips: Int
    let countriesVisited: Int
    let citiesVisited: Int
    let totalDaysTraveling: Int

    enum CodingKeys: String, CodingKey {
        case totalTrips = "total_trips"
        case countriesVisited = "countries_visited"
        case citiesVisited = "cities_visited"
        case totalDaysTraveling = "total_days_traveling"
    }
}

struct YearSummary: Codable, Identifiable {
    let year: Int
    let tripsCount: Int
    let countries: [String]
    let newCountries: [String]
    let daysAbroad: Int
    let longestTrip: LongestTrip?
    let trips: [String]  // trip IDs
    var narrative: String?

    var id: Int { year }

    enum CodingKeys: String, CodingKey {
        case year
        case tripsCount = "trips_count"
        case countries
        case newCountries = "new_countries"
        case daysAbroad = "days_abroad"
        case longestTrip = "longest_trip"
        case trips, narrative
    }
}

struct LongestTrip: Codable {
    let destination: String
    let days: Int
}

struct Trip: Codable, Identifiable {
    let id: String
    let departureDate: String
    let returnDate: String
    let durationDays: Int
    let photoCount: Int
    let countries: [String]
    let cities: [String]
    let stops: [Stop]
    var narrative: String?
    var tagline: String?

    enum CodingKeys: String, CodingKey {
        case id
        case departureDate = "departure_date"
        case returnDate = "return_date"
        case durationDays = "duration_days"
        case photoCount = "photo_count"
        case countries, cities, stops, narrative, tagline
    }
}

struct Stop: Codable, Identifiable {
    let city: String
    let country: String
    let districts: [String]
    let arrivalDate: String
    let days: Int
    let photoCount: Int
    let coordinates: Coordinate

    var id: String { "\(city)-\(country)-\(arrivalDate)" }

    enum CodingKeys: String, CodingKey {
        case city, country, districts
        case arrivalDate = "arrival_date"
        case days
        case photoCount = "photo_count"
        case coordinates
    }
}
