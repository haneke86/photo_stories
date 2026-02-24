import SwiftUI
import Photos
import SwiftData
import UIKit

/// Orchestrates the full pipeline: permission → fetch → geocode → detect → build.
/// Publishes progress state for the UI.
@MainActor
final class PipelineViewModel: ObservableObject {

    enum State {
        case needsPermission
        case denied
        case limitedNoPhotos  // User granted limited access but no geotagged photos available
        case processing
        case ready
        case error(String)
    }

    enum Step: String {
        case fetching = "Reading photo library..."
        case geocoding = "Geocoding locations..."
        case detecting = "Detecting trips..."
        case building = "Building timeline..."
        case saving = "Saving..."
    }

    @Published var state: State = .needsPermission
    @Published var currentStep: Step = .fetching
    @Published var progress: Double = 0       // 0.0 - 1.0
    @Published var progressDetail: String = ""
    @Published private(set) var timeline: Timeline?
    @Published var isRefining = false

    /// Estimated seconds remaining for geocoding, based on progress rate.
    @Published var estimatedSecondsRemaining: Int?

    private let photoService = PhotoLibraryService()
    private let geocodingService = GeocodingService()

    /// Stored records for reuse during background refinement.
    private var photoRecords: [PhotoRecord] = []

    /// Timestamp of the last successful photo fetch, for incremental refresh.
    private static let lastFetchDateKey = "lastPhotoFetchDate"

    private var lastFetchDate: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastFetchDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastFetchDateKey) }
    }

    /// SwiftData cache, created once and shared between coarse and fine passes.
    private var cache: PhotoCacheStore?

    /// Background task identifier to extend processing when app is backgrounded.
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    /// Timestamp when geocoding started, for ETA calculation.
    private var geocodingStartTime: Date?

    // MARK: - Permission

    func checkPermission() {
        let status = photoService.currentStatus()
        switch status {
        case .authorized, .limited:
            // Check for cached timeline first
            if let cached = TimelineStore.load() {
                timeline = cached
                state = .ready
            } else {
                start()
            }
        case .denied, .restricted:
            state = .denied
        default:
            state = .needsPermission
        }
    }

    func requestPermission() {
        Task {
            let status = await photoService.requestAuthorization()
            switch status {
            case .authorized, .limited:
                start()
            case .denied, .restricted:
                state = .denied
            default:
                state = .needsPermission
            }
        }
    }

    // MARK: - Pipeline

    func start() {
        state = .processing
        progress = 0
        estimatedSecondsRemaining = nil

        beginProcessingSession()

        Task {
            do {
                let fetchStart = Date()

                // Step 1: Fetch photos
                currentStep = .fetching
                progressDetail = "Scanning photo library..."
                let records = await photoService.fetchGeotaggedPhotos()

                guard !records.isEmpty else {
                    endProcessingSession()
                    // If limited access, guide user to grant full access or select geotagged photos
                    if photoService.currentStatus() == .limited {
                        state = .limitedNoPhotos
                    } else {
                        state = .error("No geotagged photos found in the last 6 years.")
                    }
                    return
                }
                progressDetail = "\(records.count) geotagged photos found"
                self.photoRecords = records

                // Initialize SwiftData cache (shared between coarse and fine passes)
                if cache == nil, let container = try? ModelContainer(for: CachedGeocode.self) {
                    cache = PhotoCacheStore(modelContainer: container)
                }

                // Step 2: Coarse geocode (0.05° grid — ~5x fewer clusters, ~2 min)
                currentStep = .geocoding
                geocodingStartTime = Date()

                let geocoded = await geocodingService.geocodePhotos(
                    records, cache: cache,
                    resolution: GeocodingService.coarseResolution
                ) { [weak self] completed, total in
                    Task { @MainActor in
                        let fraction = Double(completed) / Double(max(total, 1))
                        self?.progress = fraction
                        self?.progressDetail = "Geocoding location \(completed) of \(total)..."
                        self?.updateETA(completed: completed, total: total)
                    }
                }

                geocodingStartTime = nil
                estimatedSecondsRemaining = nil

                // Filter out records with no usable city
                let usable = geocoded.filter { $0.city != "Unknown" && !$0.city.isEmpty }

                guard !usable.isEmpty else {
                    endProcessingSession()
                    state = .error("Could not geocode any photo locations.")
                    return
                }

                // Step 3: Detect trips
                currentStep = .detecting
                progress = 0
                progressDetail = "Analyzing travel patterns..."

                let result = TimelineBuilder.build(from: usable)

                // Step 4: Save coarse timeline and show dashboard
                currentStep = .saving
                progressDetail = "Saving timeline..."
                try TimelineStore.save(result)

                endProcessingSession()

                timeline = result
                state = .ready
                self.lastFetchDate = fetchStart

                // Step 5: Kick off background refinement
                refineGeocode()

            } catch {
                endProcessingSession()
                state = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Processing Session (idle timer + background task)

    /// Keep screen awake and register a background task for extended processing.
    private func beginProcessingSession() {
        UIApplication.shared.isIdleTimerDisabled = true

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "geocoding") { [weak self] in
            // System is about to suspend — end the task gracefully.
            // SwiftData cache preserves progress; next launch resumes fast.
            self?.endBackgroundTask()
        }
    }

    /// Re-enable screen lock and end the background task.
    private func endProcessingSession() {
        UIApplication.shared.isIdleTimerDisabled = false
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    /// Estimate remaining time based on elapsed time and completion fraction.
    private func updateETA(completed: Int, total: Int) {
        guard completed > 0, let startTime = geocodingStartTime else {
            estimatedSecondsRemaining = nil
            return
        }
        let elapsed = Date().timeIntervalSince(startTime)
        let rate = elapsed / Double(completed) // seconds per cluster
        let remaining = rate * Double(total - completed)
        estimatedSecondsRemaining = max(1, Int(remaining))
    }

    // MARK: - Background Refinement

    /// Re-geocode with fine grid (0.01°) in the background, then update the timeline.
    /// Coarse clusters are already cached, so only new fine-grid clusters need API calls.
    private func refineGeocode() {
        guard !photoRecords.isEmpty else { return }

        Task {
            isRefining = true

            let refined = await geocodingService.geocodePhotos(
                photoRecords, cache: cache,
                resolution: GeocodingService.fineResolution
            ) { _, _ in
                // Silent — no progress UI for refinement
            }

            let usable = refined.filter { $0.city != "Unknown" && !$0.city.isEmpty }
            guard !usable.isEmpty else {
                isRefining = false
                return
            }

            let result = TimelineBuilder.build(from: usable)
            try? TimelineStore.save(result)

            timeline = result
            isRefining = false
        }
    }

    /// Re-scan for new photos (clears cache and re-runs pipeline).
    func refresh() {
        endProcessingSession()
        try? TimelineStore.delete()
        timeline = nil
        photoRecords = []
        isRefining = false
        start()
    }

    /// Scan only photos added since the last fetch and merge into existing timeline.
    /// Called by pull-to-refresh on the Explore tab.
    func incrementalRefresh() async {
        guard let since = lastFetchDate else {
            // No previous fetch date — fall back to full refresh
            start()
            return
        }

        let fetchStart = Date()
        let newRecords = await photoService.fetchGeotaggedPhotos(since: since)

        guard !newRecords.isEmpty else {
            // No new photos — nothing to do
            return
        }

        // Initialize cache if needed
        if cache == nil, let container = try? ModelContainer(for: CachedGeocode.self) {
            cache = PhotoCacheStore(modelContainer: container)
        }

        // Geocode new photos only
        let geocoded = await geocodingService.geocodePhotos(
            newRecords, cache: cache,
            resolution: GeocodingService.fineResolution
        ) { _, _ in }

        let usableNew = geocoded.filter { $0.city != "Unknown" && !$0.city.isEmpty }
        guard !usableNew.isEmpty else {
            self.lastFetchDate = fetchStart
            return
        }

        // Merge with existing records
        let existingIds = Set(photoRecords.map(\.id))
        let deduped = usableNew.filter { !existingIds.contains($0.id) }
        photoRecords.append(contentsOf: deduped)

        // Re-geocode all existing records too (cache will serve them instantly)
        let allGeocoded = await geocodingService.geocodePhotos(
            photoRecords, cache: cache,
            resolution: GeocodingService.fineResolution
        ) { _, _ in }

        let allUsable = allGeocoded.filter { $0.city != "Unknown" && !$0.city.isEmpty }
        guard !allUsable.isEmpty else { return }

        // Rebuild timeline
        let result = TimelineBuilder.build(from: allUsable)
        try? TimelineStore.save(result)

        timeline = result
        self.lastFetchDate = fetchStart
    }
}
