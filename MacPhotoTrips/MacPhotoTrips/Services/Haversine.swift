import Foundation

/// Great-circle distance utilities.
/// Port of trips.py:26-34 and :65-71.
enum Haversine {

    /// Earth radius in km.
    static let earthRadiusKm: Double = 6371.0

    /// Great-circle distance between two points in km.
    /// Port of trips.py:26-34 (_haversine_km).
    static func distanceKm(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        return earthRadiusKm * 2 * asin(sqrt(a))
    }

    /// Check if coordinates are within the home zone.
    /// Port of trips.py:65-71 (_is_home).
    static func isHome(
        lat: Double, lon: Double,
        homeBase: HomeBase
    ) -> Bool {
        let dist = distanceKm(
            lat1: lat, lon1: lon,
            lat2: homeBase.center.lat, lon2: homeBase.center.lon
        )
        return dist <= homeBase.radiusKm
    }
}
