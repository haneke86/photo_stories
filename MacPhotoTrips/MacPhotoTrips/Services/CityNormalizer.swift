import Foundation

/// Port of extractors/normalize.py — shared city normalization rules.
///
/// Apple's reverse-geocoded city field is district-level for big metros
/// in certain countries. These rules normalize to metro level.
enum CityNormalizer {

    /// French region → metro city mapping.
    private static let franceRegionToMetro: [String: String] = [
        "Île-de-France": "Paris",
    ]

    /// ASCII→Unicode fixes for geocoder inconsistencies.
    static let cityNameFixes: [String: String] = [
        "Mugla": "Muğla",
        "Izmir": "İzmir",
        "Canakkale": "Çanakkale",
        "Sanliurfa": "Şanlıurfa",
    ]

    /// Normalize city to metro level.
    ///
    /// Port of extract.py:99-133 (_normalize_city):
    /// - Turkey: _city=Beşiktaş, _state=Istanbul → use state
    /// - UK/Greece: _city=Hounslow, _subAdmin=London → use subAdmin
    /// - France: _city=Clichy, _state=Île-de-France → use state→metro mapping
    /// - Ireland: _city=Dublin 2 → strip postal district number
    /// - US/Italy/others: _city is already correct
    static func normalize(
        country: String?,
        city: String?,
        state: String?,
        subAdmin: String?
    ) -> String {
        // Handle Turkey (multiple spellings)
        if let country, isTurkey(country), let state, !state.isEmpty {
            return state
        }
        if let country, (country == "United Kingdom" || country == "Greece"),
           let subAdmin, !subAdmin.isEmpty {
            return subAdmin
        }
        if let country, country == "France", let state, !state.isEmpty {
            return franceRegionToMetro[state] ?? city ?? state
        }
        if let country, country == "Ireland", let city, !city.isEmpty {
            return stripPostalDistrict(city)
        }
        return city ?? subAdmin ?? state ?? "Unknown"
    }

    /// Check if country name is any variant of Turkey.
    private static func isTurkey(_ country: String) -> Bool {
        ["Türkiye", "Turkey", "Turkiye"].contains(country)
    }

    /// Strip postal district numbers: "Dublin 2" → "Dublin".
    static func stripPostalDistrict(_ city: String) -> String {
        // Match: "City Name 123" → "City Name"
        let pattern = #"^(.+?)\s+\d+$"#
        if let range = city.range(of: pattern, options: .regularExpression) {
            let fullMatch = city[range]
            // Extract just the city part (before trailing digits)
            if let spaceRange = fullMatch.range(of: #"\s+\d+$"#, options: .regularExpression) {
                return String(city[city.startIndex..<spaceRange.lowerBound])
            }
        }
        return city
    }

    /// Apply ASCII→Unicode fixes.
    static func applyNameFixes(_ city: String) -> String {
        cityNameFixes[city] ?? city
    }
}
