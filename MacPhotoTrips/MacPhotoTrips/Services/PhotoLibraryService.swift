import Photos
import CoreLocation

/// Handles PHPhotoLibrary authorization and PHAsset fetching.
/// Extracts raw photo metadata (date, location, filename) from the device library.
actor PhotoLibraryService {

    /// Request photo library access and return the authorization status.
    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Current authorization status (no prompt).
    nonisolated func currentStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Fetch all geotagged photos from the last N years.
    /// Returns raw records with coordinates but no city/country (those need geocoding).
    func fetchGeotaggedPhotos(yearsBack: Int = 6) -> [PhotoRecord] {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .year, value: -yearsBack, to: Date()) else {
            return []
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@", cutoff as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let assets = PHAsset.fetchAssets(with: .image, options: options)

        var records: [PhotoRecord] = []
        records.reserveCapacity(assets.count)

        assets.enumerateObjects { asset, _, _ in
            guard let location = asset.location,
                  let date = asset.creationDate else { return }

            let coord = location.coordinate
            // Filter out invalid coordinates (Apple uses -180 as sentinel)
            guard coord.latitude != -180.0, coord.longitude != -180.0 else { return }

            let record = PhotoRecord(
                id: asset.localIdentifier,
                latitude: coord.latitude,
                longitude: coord.longitude,
                date: date,
                filename: PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "photo_\(asset.localIdentifier)",
                country: "",   // filled by GeocodingService
                city: "",
                district: "",
                state: ""
            )
            records.append(record)
        }

        return records
    }

    /// Fetch only geotagged photos created after the given date.
    /// Returns an empty array if no new photos exist.
    func fetchGeotaggedPhotos(since date: Date) -> [PhotoRecord] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate > %@", date as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let assets = PHAsset.fetchAssets(with: .image, options: options)

        var records: [PhotoRecord] = []
        records.reserveCapacity(assets.count)

        assets.enumerateObjects { asset, _, _ in
            guard let location = asset.location,
                  let date = asset.creationDate else { return }

            let coord = location.coordinate
            guard coord.latitude != -180.0, coord.longitude != -180.0 else { return }

            let record = PhotoRecord(
                id: asset.localIdentifier,
                latitude: coord.latitude,
                longitude: coord.longitude,
                date: date,
                filename: PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "photo_\(asset.localIdentifier)",
                country: "",
                city: "",
                district: "",
                state: ""
            )
            records.append(record)
        }

        return records
    }
}
