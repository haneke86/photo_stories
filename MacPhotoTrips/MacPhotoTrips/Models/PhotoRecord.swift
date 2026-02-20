import Foundation
import CoreLocation

/// A single photo's metadata extracted from the library.
/// Mirrors the Python PhotoRecord TypedDict from extractors/base.py.
struct PhotoRecord: Identifiable {
    let id: String          // unique identifier (asset localIdentifier)
    let latitude: Double
    let longitude: Double
    let date: Date
    let filename: String
    var country: String
    var city: String        // metro-level (normalized)
    var district: String
    var state: String

    var year: Int { Calendar.current.component(.year, from: date) }
    var month: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var dateOnly: DateComponents {
        Calendar.current.dateComponents([.year, .month, .day], from: date)
    }
}
