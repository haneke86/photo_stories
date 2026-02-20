import Foundation

/// Detect trips from chronologically sorted photo data.
/// Port of trips.py:74-228 (detect_trips, _build_trip, _merge_same_city_stops).
enum TripDetector {

    /// Gap threshold: if no geotagged photos for N days during travel, assume trip ended.
    /// Set to 7 because some photos lack GPS data, creating artificial gaps.
    static let tripGapDays = 7

    // MARK: - Public API

    /// Detect trips from photo records and a known home base.
    /// Port of trips.py:74-119 (detect_trips).
    ///
    /// A trip is a contiguous stretch of days with photos outside the home zone.
    /// Multi-stop trips (multiple countries/cities without returning home) are
    /// grouped as one trip with multiple stops.
    static func detect(from records: [PhotoRecord], homeBase: HomeBase) -> [Trip] {
        let sorted = records.sorted { $0.date < $1.date }

        var trips: [Trip] = []
        var currentTripPhotos: [PhotoRecord] = []

        for record in sorted {
            let atHome = Haversine.isHome(lat: record.latitude, lon: record.longitude, homeBase: homeBase)

            if atHome {
                if !currentTripPhotos.isEmpty {
                    if let trip = buildTrip(from: currentTripPhotos) {
                        trips.append(trip)
                    }
                    currentTripPhotos = []
                }
            } else {
                // Check for gap — if too long since last photo, split trip
                if let lastPhoto = currentTripPhotos.last {
                    let gap = Calendar.current.dateComponents([.day], from: lastPhoto.date, to: record.date).day ?? 0
                    if gap > tripGapDays {
                        if let trip = buildTrip(from: currentTripPhotos) {
                            trips.append(trip)
                        }
                        currentTripPhotos = []
                    }
                }
                currentTripPhotos.append(record)
            }
        }

        // Don't forget last trip if it didn't end with home
        if !currentTripPhotos.isEmpty {
            if let trip = buildTrip(from: currentTripPhotos) {
                trips.append(trip)
            }
        }

        return trips
    }

    // MARK: - Trip Building

    /// Build a Trip from a list of photo records.
    /// Port of trips.py:122-179 (_build_trip).
    private static func buildTrip(from photos: [PhotoRecord]) -> Trip? {
        guard !photos.isEmpty else { return nil }

        let sorted = photos.sorted { $0.date < $1.date }
        let departure = Calendar.current.startOfDay(for: sorted.first!.date)
        let returnDate = Calendar.current.startOfDay(for: sorted.last!.date)
        let duration = max(1, Calendar.current.dateComponents([.day], from: departure, to: returnDate).day! + 1)

        // Build stops: group consecutive photos by (city, country)
        var stops: [WorkingStop] = []
        var currentStop: WorkingStop?

        for photo in sorted {
            let key = StopKey(city: photo.city, country: photo.country)

            if currentStop == nil || currentStop!.key != key {
                if let stop = currentStop {
                    stops.append(stop)
                }
                currentStop = WorkingStop(key: key)
            }
            currentStop!.addPhoto(photo)
        }

        if let stop = currentStop {
            stops.append(stop)
        }

        // Finalize and merge same-city stops
        var finalStops = stops.map { $0.finalize() }
        finalStops = mergeSameCityStops(finalStops)

        // Trip-level summary
        var allCountries: [String] = []
        var allCities: [String] = []
        for stop in finalStops {
            if !allCountries.contains(stop.country) { allCountries.append(stop.country) }
            if !allCities.contains(stop.city) { allCities.append(stop.city) }
        }

        // Generate readable trip ID
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let departureStr = dateFormatter.string(from: departure)
        let returnStr = dateFormatter.string(from: returnDate)
        let primary = allCities.count == 1 ? allCities[0] : allCountries[0]
        let tripId = "\(departureStr)-\(primary.lowercased().replacingOccurrences(of: " ", with: "-"))"

        return Trip(
            id: tripId,
            departureDate: departureStr,
            returnDate: returnStr,
            durationDays: duration,
            photoCount: photos.count,
            countries: allCountries,
            cities: allCities,
            stops: finalStops
        )
    }

    // MARK: - Merge Same City Stops

    /// Merge all stops in the same city within a trip, preserving order.
    /// Port of trips.py:201-228 (_merge_same_city_stops).
    ///
    /// Handles cases like Muğla → Paris → Muğla by consolidating both Muğla stops.
    private static func mergeSameCityStops(_ stops: [Stop]) -> [Stop] {
        guard !stops.isEmpty else { return stops }

        var seen: [StopKey: Int] = [:]  // key → index in merged
        var merged: [Stop] = []

        for stop in stops {
            let key = StopKey(city: stop.city, country: stop.country)

            if let existingIndex = seen[key] {
                // Merge into existing stop
                var prev = merged[existingIndex]
                let combinedDistricts = Array(Set(prev.districts + stop.districts)).sorted()
                prev = Stop(
                    city: prev.city,
                    country: prev.country,
                    districts: combinedDistricts,
                    arrivalDate: prev.arrivalDate,
                    days: prev.days + stop.days,
                    photoCount: prev.photoCount + stop.photoCount,
                    coordinates: prev.coordinates
                )
                merged[existingIndex] = prev
            } else {
                seen[key] = merged.count
                merged.append(stop)
            }
        }

        return merged
    }
}

// MARK: - Internal Types

private struct StopKey: Hashable {
    let city: String
    let country: String
}

/// Mutable working stop accumulator (parallels Python's working dict).
private struct WorkingStop {
    let key: StopKey
    var districts: Set<String> = []
    var dates: Set<Date> = []
    var lats: [Double] = []
    var lons: [Double] = []
    var photoCount = 0

    mutating func addPhoto(_ photo: PhotoRecord) {
        if !photo.district.isEmpty {
            districts.insert(photo.district)
        }
        dates.insert(Calendar.current.startOfDay(for: photo.date))
        lats.append(photo.latitude)
        lons.append(photo.longitude)
        photoCount += 1
    }

    func finalize() -> Stop {
        let sortedDates = dates.sorted()
        let days = max(1,
            (Calendar.current.dateComponents([.day],
                from: sortedDates.first!,
                to: sortedDates.last!).day ?? 0) + 1
        )

        let avgLat = lats.reduce(0, +) / Double(lats.count)
        let avgLon = lons.reduce(0, +) / Double(lons.count)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        return Stop(
            city: key.city,
            country: key.country,
            districts: districts.sorted(),
            arrivalDate: dateFormatter.string(from: sortedDates.first!),
            days: days,
            photoCount: photoCount,
            coordinates: Coordinate(
                lat: (avgLat * 10000).rounded() / 10000,
                lon: (avgLon * 10000).rounded() / 10000
            )
        )
    }
}
