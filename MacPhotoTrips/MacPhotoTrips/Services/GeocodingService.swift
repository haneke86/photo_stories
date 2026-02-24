import CoreLocation
import Foundation

/// Reverse geocodes photo coordinates using CLGeocoder with clustering and rate limiting.
///
/// Strategy (the hard part — CLGeocoder is rate-limited at ~50 req/min):
/// 1. Cluster: Round coordinates to 0.01° grid (~1km cells). 10k photos → ~300 clusters.
/// 2. Batch geocode: One CLGeocoder call per cluster at ~45 req/min (1.3s delay).
/// 3. Cache: SwiftData cache makes subsequent runs instant.
actor GeocodingService {

    /// Default grid resolution for coordinate clustering (0.01° ≈ 1km).
    private let gridResolution: Double = 0.01

    /// Coarse grid resolution for fast first pass (0.05° ≈ 5km).
    static let coarseResolution: Double = 0.05

    /// Fine grid resolution for detailed second pass (0.01° ≈ 1km).
    static let fineResolution: Double = 0.01

    /// Delay between geocoder calls in seconds (1.3s ≈ 45 req/min).
    private let requestDelay: TimeInterval = 1.3

    /// Maximum retries per cluster on rate-limit error.
    private let maxRetries = 3

    private let geocoder = CLGeocoder()

    /// Progress callback: (completed, total).
    typealias ProgressHandler = @Sendable (Int, Int) -> Void

    // MARK: - Clustering

    /// A grid cell key for coordinate clustering.
    struct GridKey: Hashable {
        let latBucket: Int
        let lonBucket: Int

        init(lat: Double, lon: Double, resolution: Double) {
            self.latBucket = Int((lat / resolution).rounded(.down))
            self.lonBucket = Int((lon / resolution).rounded(.down))
        }

        /// Representative coordinate (center of the grid cell).
        func centerCoordinate(resolution: Double) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: (Double(latBucket) + 0.5) * resolution,
                longitude: (Double(lonBucket) + 0.5) * resolution
            )
        }
    }

    /// Result of geocoding a single cluster.
    struct GeoResult {
        let country: String
        let city: String
        let state: String
        let subAdmin: String
        let district: String
    }

    // MARK: - Public API

    /// Geocode all photos by clustering, batch geocoding, and applying results.
    /// Returns updated records with country/city/state/district filled in.
    /// - Parameter resolution: Grid cell size for clustering. Use `coarseResolution` (0.05°) for fast
    ///   first pass or `fineResolution` (0.01°) for detailed results. Defaults to `self.gridResolution`.
    func geocodePhotos(
        _ records: [PhotoRecord],
        cache: PhotoCacheStore?,
        resolution: Double? = nil,
        progress: ProgressHandler? = nil
    ) async -> [PhotoRecord] {
        let res = resolution ?? gridResolution

        // 1. Cluster photos by grid cell
        var clusters: [GridKey: [Int]] = [:]  // gridKey → indices into records
        for (index, record) in records.enumerated() {
            let key = GridKey(lat: record.latitude, lon: record.longitude, resolution: res)
            clusters[key, default: []].append(index)
        }

        // 2. Check cache for already-geocoded clusters
        var results: [GridKey: GeoResult] = [:]
        var uncached: [GridKey] = []

        for key in clusters.keys {
            if let cached = await cache?.lookup(latBucket: key.latBucket, lonBucket: key.lonBucket) {
                results[key] = cached
            } else {
                uncached.append(key)
            }
        }

        let total = uncached.count
        var completed = 0

        // 3. Batch geocode uncached clusters
        for key in uncached {
            let coord = key.centerCoordinate(resolution: res)
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)

            if let result = await geocodeWithRetry(location: location) {
                results[key] = result
                await cache?.store(
                    latBucket: key.latBucket, lonBucket: key.lonBucket,
                    result: result
                )
            }

            completed += 1
            progress?(completed, total)

            // Rate limit: wait between requests
            if completed < total {
                try? await Task.sleep(for: .milliseconds(Int(requestDelay * 1000)))
            }
        }

        // 4. Apply results to all records
        var updated = records
        for (key, indices) in clusters {
            guard let result = results[key] else { continue }

            let normalizedCity = CityNormalizer.normalize(
                country: result.country,
                city: result.city,
                state: result.state,
                subAdmin: result.subAdmin
            )
            let fixedCity = CityNormalizer.applyNameFixes(normalizedCity)

            for index in indices {
                updated[index].country = result.country
                updated[index].city = fixedCity
                updated[index].state = result.state
                updated[index].district = result.district
            }
        }

        return updated
    }

    // MARK: - Private

    /// Geocode a location with exponential backoff on rate-limit errors.
    private func geocodeWithRetry(location: CLLocation) async -> GeoResult? {
        var delay: TimeInterval = 2.0

        for attempt in 0..<maxRetries {
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                guard let placemark = placemarks.first else { return nil }

                return GeoResult(
                    country: placemark.country ?? "",
                    city: placemark.locality ?? "",
                    state: placemark.administrativeArea ?? "",
                    subAdmin: placemark.subAdministrativeArea ?? "",
                    district: placemark.subLocality ?? ""
                )
            } catch {
                let nsError = error as NSError
                // CLError.network (code 2) often means rate-limited
                if nsError.domain == kCLErrorDomain && nsError.code == 2 && attempt < maxRetries - 1 {
                    try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                    delay *= 2  // exponential backoff
                    continue
                }
                return nil
            }
        }
        return nil
    }
}
