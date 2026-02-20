import CoreLocation

/// CLPlacemark → Python field mapping reference.
///
/// | CLPlacemark property       | Python field              | Usage                          |
/// |---------------------------|---------------------------|--------------------------------|
/// | .country                  | _country                  | Country name                   |
/// | .locality                 | _city                     | City (district-level for Turkey/UK) |
/// | .administrativeArea       | _state                    | State/province                 |
/// | .subAdministrativeArea    | _subAdministrativeArea    | County-level (UK/Greece)       |
/// | .subLocality              | district                  | Neighborhood level             |
///
/// This extension provides convenient access matching Python field names.
extension CLPlacemark {

    /// Country name (e.g. "Türkiye", "United Kingdom").
    var countryName: String { country ?? "" }

    /// City name — may be district-level for Turkey/UK (needs normalization).
    var cityName: String { locality ?? "" }

    /// State/province/administrative area.
    var stateName: String { administrativeArea ?? "" }

    /// Sub-administrative area (county-level, used for UK/Greece normalization).
    var subAdminName: String { subAdministrativeArea ?? "" }

    /// Sub-locality / neighborhood / district.
    var districtName: String { subLocality ?? "" }
}
