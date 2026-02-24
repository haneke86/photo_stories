import Foundation

/// Auto-detect home base as the city with the most photo-days.
/// Port of trips.py:37-62 (detect_home_base).
enum HomeDetector {

    /// Distance threshold for "home zone" in km.
    static let homeRadiusKm: Double = 30.0

    /// Detect home base from photo records.
    /// The home is the (city, country) pair with the most unique photo-days
    /// (not photo count — avoids bias from tourist bursts).
    static func detect(from records: [PhotoRecord]) -> HomeBase {
        guard !records.isEmpty else {
            return HomeBase(city: "Unknown", country: "Unknown",
                          center: Coordinate(lat: 0, lon: 0), radiusKm: homeRadiusKm)
        }

        // Count unique days per (city, country)
        struct CityKey: Hashable {
            let city: String
            let country: String
        }

        var cityDays: [CityKey: Set<String>] = [:]  // key → set of date strings

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for record in records {
            let key = CityKey(city: record.city, country: record.country)
            let dateStr = dateFormatter.string(from: record.date)
            cityDays[key, default: []].insert(dateStr)
        }

        // Find city with most unique days
        guard let topCity = cityDays.max(by: { $0.value.count < $1.value.count }) else {
            return HomeBase(city: "Unknown", country: "Unknown",
                          center: Coordinate(lat: 0, lon: 0), radiusKm: homeRadiusKm)
        }

        // Compute median lat/lon from home city photos
        let homePhotos = records.filter { $0.city == topCity.key.city && $0.country == topCity.key.country }
        let lats = homePhotos.map(\.latitude).sorted()
        let lons = homePhotos.map(\.longitude).sorted()

        let medianLat = median(lats)
        let medianLon = median(lons)

        return HomeBase(
            city: topCity.key.city,
            country: topCity.key.country,
            center: Coordinate(
                lat: (medianLat * 10000).rounded() / 10000,
                lon: (medianLon * 10000).rounded() / 10000
            ),
            radiusKm: homeRadiusKm
        )
    }

    private static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
