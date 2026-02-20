import SwiftUI
import Photos
import SwiftData

/// Orchestrates the full pipeline: permission → fetch → geocode → detect → build.
/// Publishes progress state for the UI.
@MainActor
final class PipelineViewModel: ObservableObject {

    enum State {
        case needsPermission
        case denied
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

    private let photoService = PhotoLibraryService()
    private let geocodingService = GeocodingService()

    /// Stored records for reuse during background refinement.
    private var photoRecords: [PhotoRecord] = []

    /// SwiftData cache, created once and shared between coarse and fine passes.
    private var cache: PhotoCacheStore?

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

        Task {
            do {
                // Step 1: Fetch photos
                currentStep = .fetching
                progressDetail = "Scanning photo library..."
                let records = await photoService.fetchGeotaggedPhotos()

                guard !records.isEmpty else {
                    state = .error("No geotagged photos found in the last 6 years.")
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

                let geocoded = await geocodingService.geocodePhotos(
                    records, cache: cache,
                    resolution: GeocodingService.coarseResolution
                ) { [weak self] completed, total in
                    Task { @MainActor in
                        self?.progress = Double(completed) / Double(max(total, 1))
                        self?.progressDetail = "Geocoding location \(completed) of \(total)..."
                    }
                }

                // Filter out records with no usable city
                let usable = geocoded.filter { $0.city != "Unknown" && !$0.city.isEmpty }

                guard !usable.isEmpty else {
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

                timeline = result
                state = .ready

                // Step 5: Kick off background refinement
                refineGeocode()

            } catch {
                state = .error(error.localizedDescription)
            }
        }
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
        try? TimelineStore.delete()
        timeline = nil
        photoRecords = []
        isRefining = false
        start()
    }
}
