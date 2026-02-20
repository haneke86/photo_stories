import Foundation

/// Country name → emoji flag mapping.
/// Uses Unicode regional indicator symbols derived from ISO 3166-1 alpha-2 codes.
enum CountryFlags {

    /// Known country name → ISO 3166-1 alpha-2 code.
    private static let countryToCode: [String: String] = [
        "Türkiye": "TR", "Turkey": "TR", "Turkiye": "TR",
        "United Kingdom": "GB", "Greece": "GR", "France": "FR",
        "Italy": "IT", "Spain": "ES", "Germany": "DE",
        "Netherlands": "NL", "Belgium": "BE", "Austria": "AT",
        "Switzerland": "CH", "Portugal": "PT", "Ireland": "IE",
        "United States": "US", "Canada": "CA", "Mexico": "MX",
        "Japan": "JP", "South Korea": "KR", "China": "CN",
        "Thailand": "TH", "Vietnam": "VN", "Indonesia": "ID",
        "India": "IN", "Australia": "AU", "New Zealand": "NZ",
        "Brazil": "BR", "Argentina": "AR", "Colombia": "CO",
        "Egypt": "EG", "Morocco": "MA", "South Africa": "ZA",
        "United Arab Emirates": "AE", "Saudi Arabia": "SA",
        "Israel": "IL", "Jordan": "JO", "Lebanon": "LB",
        "Croatia": "HR", "Montenegro": "ME", "Slovenia": "SI",
        "Czech Republic": "CZ", "Czechia": "CZ",
        "Poland": "PL", "Hungary": "HU", "Romania": "RO",
        "Bulgaria": "BG", "Serbia": "RS", "Albania": "AL",
        "North Macedonia": "MK", "Bosnia and Herzegovina": "BA",
        "Norway": "NO", "Sweden": "SE", "Denmark": "DK",
        "Finland": "FI", "Iceland": "IS", "Estonia": "EE",
        "Latvia": "LV", "Lithuania": "LT",
        "Georgia": "GE", "Armenia": "AM", "Azerbaijan": "AZ",
        "Russia": "RU", "Ukraine": "UA",
        "Singapore": "SG", "Malaysia": "MY", "Philippines": "PH",
        "Sri Lanka": "LK", "Nepal": "NP", "Maldives": "MV",
        "Cuba": "CU", "Jamaica": "JM", "Dominican Republic": "DO",
        "Costa Rica": "CR", "Panama": "PA", "Peru": "PE",
        "Chile": "CL", "Ecuador": "EC", "Bolivia": "BO",
        "Cyprus": "CY", "Malta": "MT", "Luxembourg": "LU",
        "Monaco": "MC", "Andorra": "AD", "Liechtenstein": "LI",
        "Tunisia": "TN", "Kenya": "KE", "Tanzania": "TZ",
        "Ethiopia": "ET", "Nigeria": "NG", "Ghana": "GH",
        "Senegal": "SN", "Oman": "OM", "Qatar": "QA",
        "Bahrain": "BH", "Kuwait": "KW",
    ]

    /// Convert an ISO 3166-1 alpha-2 code to an emoji flag.
    /// Each letter maps to a Unicode regional indicator symbol: A=🇦, B=🇧, etc.
    static func flag(forCode code: String) -> String {
        let base: UInt32 = 0x1F1E6  // Regional Indicator Symbol Letter A
        return code.uppercased().unicodeScalars.compactMap { scalar in
            guard let letter = Unicode.Scalar(base + scalar.value - 65) else { return nil }
            return String(letter)
        }.joined()
    }

    /// Get emoji flag for a country name.
    static func flag(forCountry country: String) -> String {
        guard let code = countryToCode[country] else { return "" }
        return flag(forCode: code)
    }
}
