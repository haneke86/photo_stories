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
        case stories = "Generating storylines..."
    }

    @Published var state: State = .needsPermission
    @Published var currentStep: Step = .fetching
    @Published var progress: Double = 0       // 0.0 - 1.0
    @Published var progressDetail: String = ""
    @Published private(set) var timeline: Timeline?
    @Published private(set) var narrativeResult: NarrativeResult?

    private let photoService = PhotoLibraryService()
    private let geocodingService = GeocodingService()

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

                // Step 2: Geocode
                currentStep = .geocoding

                // Get SwiftData container for cache
                let cache: PhotoCacheStore?
                if let container = try? ModelContainer(for: CachedGeocode.self) {
                    cache = PhotoCacheStore(modelContainer: container)
                } else {
                    cache = nil
                }

                let geocoded = await geocodingService.geocodePhotos(records, cache: cache) { [weak self] completed, total in
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

                // Step 4: Save
                currentStep = .saving
                progressDetail = "Saving timeline..."
                try TimelineStore.save(result)

                // Step 5: Generate narratives (non-blocking)
                currentStep = .stories
                progressDetail = "Writing trip stories..."

                if let provider = AnthropicDirectProvider() {
                    let storyService = StoryService(provider: provider)
                    let narratives = await storyService.generateIfNeeded(timeline: result)
                    if let narratives = narratives {
                        self.narrativeResult = narratives
                    }
                }

                timeline = result
                state = .ready

            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    /// Re-scan for new photos (clears cache and re-runs pipeline).
    func refresh() {
        try? TimelineStore.delete()
        timeline = nil
        start()
    }
}
