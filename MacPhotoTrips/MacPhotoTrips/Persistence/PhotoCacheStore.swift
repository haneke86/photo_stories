import SwiftData
import Foundation

/// SwiftData model for caching geocoded coordinate clusters.
/// After first-run geocoding (~7 min for 300 clusters), subsequent runs are instant.
@Model
final class CachedGeocode {
    @Attribute(.unique) var gridKey: String   // "latBucket:lonBucket"
    var country: String
    var city: String
    var state: String
    var subAdmin: String
    var district: String
    var createdAt: Date

    init(latBucket: Int, lonBucket: Int, country: String, city: String,
         state: String, subAdmin: String, district: String) {
        self.gridKey = "\(latBucket):\(lonBucket)"
        self.country = country
        self.city = city
        self.state = state
        self.subAdmin = subAdmin
        self.district = district
        self.createdAt = Date()
    }
}

/// Actor-isolated store for reading/writing geocode cache via SwiftData.
actor PhotoCacheStore {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Look up a cached geocode result by grid bucket.
    @MainActor
    func lookup(latBucket: Int, lonBucket: Int) -> GeocodingService.GeoResult? {
        let key = "\(latBucket):\(lonBucket)"
        let context = modelContainer.mainContext

        let descriptor = FetchDescriptor<CachedGeocode>(
            predicate: #Predicate { $0.gridKey == key }
        )

        guard let cached = try? context.fetch(descriptor).first else { return nil }

        return GeocodingService.GeoResult(
            country: cached.country,
            city: cached.city,
            state: cached.state,
            subAdmin: cached.subAdmin,
            district: cached.district
        )
    }

    /// Store a geocode result in the cache.
    @MainActor
    func store(latBucket: Int, lonBucket: Int, result: GeocodingService.GeoResult) {
        let context = modelContainer.mainContext
        let cached = CachedGeocode(
            latBucket: latBucket, lonBucket: lonBucket,
            country: result.country, city: result.city,
            state: result.state, subAdmin: result.subAdmin,
            district: result.district
        )
        context.insert(cached)
        try? context.save()
    }
}
