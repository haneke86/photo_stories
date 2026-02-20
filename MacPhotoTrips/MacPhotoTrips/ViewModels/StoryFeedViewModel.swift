import Foundation

/// Manages the story feed — loading cache, orchestrating generation, and exposing cards.
@MainActor
final class StoryFeedViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case loading       // Loading cached cards
        case generating    // Actively generating new cards
        case partial       // Some cards loaded, still generating
        case ready         // All done
        case error(String)
    }

    @Published var state: State = .idle
    @Published var cards: [StoryCard] = []
    @Published var generationProgress: String = ""
    @Published var isGenerating = false

    private let catalog: StoryCatalog
    private var generator: StoryGenerator?
    private let pipeline: PipelineViewModel

    init(pipeline: PipelineViewModel) {
        self.pipeline = pipeline
        self.catalog = StoryCatalog()
    }

    /// Load cached cards on startup.
    func loadCachedCards() async {
        state = .loading
        let cached = await catalog.loadAll()
        if !cached.isEmpty {
            cards = sortCards(cached)
            state = .ready
        } else {
            state = .idle
        }
    }

    /// Start generating stories from the timeline.
    func generate(timeline: Timeline) async {
        guard !isGenerating else { return }
        isGenerating = true

        // Wait for background refinement
        if pipeline.isRefining {
            generationProgress = "Waiting for best data..."
            while pipeline.isRefining {
                try? await Task.sleep(for: .milliseconds(500))
            }
        }

        guard let provider = AnthropicDirectProvider() else {
            state = .error("No API key configured. Set ANTHROPIC_API_KEY before building.")
            isGenerating = false
            return
        }

        state = cards.isEmpty ? .generating : .partial
        generationProgress = "Crafting stories..."

        let generator = StoryGenerator(provider: provider, catalog: catalog)
        self.generator = generator

        await generator.start(timeline: timeline) { [weak self] card in
            guard let self else { return }
            // Insert maintaining sort order
            if !self.cards.contains(where: { $0.id == card.id }) {
                self.cards.append(card)
                self.cards = self.sortCards(self.cards)
            }
            if self.state == .generating || self.state == .idle {
                self.state = .partial
            }
        }

        state = .ready
        isGenerating = false
        generationProgress = ""
    }

    /// Whether the LLM provider is available.
    var isAvailable: Bool {
        AnthropicDirectProvider()?.isAvailable ?? false
    }

    /// Sort cards: interleave by type, with trips and years first.
    private func sortCards(_ cards: [StoryCard]) -> [StoryCard] {
        // Group by type
        var byType: [StoryType: [StoryCard]] = [:]
        for card in cards {
            byType[card.type, default: []].append(card)
        }

        // Sort within each type by generatedAt descending
        for type in byType.keys {
            byType[type]?.sort { $0.generatedAt > $1.generatedAt }
        }

        // Interleave: trip, year, season, location, trip, year, ...
        let typeOrder: [StoryType] = [.trip, .yearInReview, .season, .locationSpotlight]
        var result: [StoryCard] = []
        var indices: [StoryType: Int] = [:]

        while result.count < cards.count {
            var added = false
            for type in typeOrder {
                let idx = indices[type, default: 0]
                if let items = byType[type], idx < items.count {
                    result.append(items[idx])
                    indices[type] = idx + 1
                    added = true
                }
            }
            if !added { break }
        }

        return result
    }
}
