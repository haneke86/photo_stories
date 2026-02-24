import Foundation

/// Orchestrates batch story generation with interleaving and caching.
actor StoryGenerator {
    private let provider: LLMProvider
    private let catalog: StoryCatalog
    private var prompts: [StoryPrompt] = []
    private var timelineHash: String = ""

    init(provider: LLMProvider, catalog: StoryCatalog) {
        self.provider = provider
        self.catalog = catalog
    }

    /// Build the full prompt catalog, filter cached, interleave by type, and generate in batches.
    /// Calls `onCardGenerated` on each new card (on MainActor).
    func start(
        timeline: Timeline,
        onCardGenerated: @MainActor @Sendable (StoryCard) -> Void
    ) async {
        timelineHash = StoryCatalog.hash(for: timeline)

        // Invalidate stale cache
        await catalog.invalidateStale(currentHash: timelineHash)

        // Build all prompts
        let allPrompts = StoryPromptBuilder.buildAll(from: timeline)

        // Filter out already-cached
        var uncached: [StoryPrompt] = []
        for prompt in allPrompts {
            let cached = await catalog.isCached(id: prompt.storyId, hash: timelineHash)
            if !cached {
                uncached.append(prompt)
            }
        }

        // Interleave by type for feed diversity
        prompts = interleave(uncached)

        // Generate in batches
        let initialBatchSize = min(5, prompts.count)
        if initialBatchSize > 0 {
            await generateBatch(
                prompts: Array(prompts.prefix(initialBatchSize)),
                onCardGenerated: onCardGenerated
            )
        }

        // Background batches of 3
        var offset = initialBatchSize
        while offset < prompts.count {
            // 1s pause between batches
            try? await Task.sleep(for: .seconds(1))

            let end = min(offset + 3, prompts.count)
            let batch = Array(prompts[offset..<end])
            await generateBatch(prompts: batch, onCardGenerated: onCardGenerated)
            offset = end
        }
    }

    /// Generate a batch concurrently (up to 3 parallel within a batch).
    private func generateBatch(
        prompts: [StoryPrompt],
        onCardGenerated: @MainActor @Sendable (StoryCard) -> Void
    ) async {
        await withTaskGroup(of: StoryCard?.self) { group in
            for prompt in prompts {
                group.addTask { [provider, timelineHash, catalog] in
                    do {
                        let response = try await provider.generateSingleStory(
                            systemPrompt: prompt.systemPrompt,
                            userMessage: prompt.userMessage
                        )

                        let card = StoryCard(
                            id: prompt.storyId,
                            type: prompt.type,
                            title: response.title,
                            tagline: response.tagline,
                            narrative: response.narrative,
                            generatedAt: Date(),
                            flags: prompt.flags,
                            countries: prompt.countries,
                            dateLabel: prompt.dateLabel,
                            durationLabel: prompt.durationLabel,
                            associatedTripIds: prompt.associatedTripIds,
                            timelineHash: timelineHash
                        )

                        await catalog.save(card)
                        return card
                    } catch {
                        print("Story generation failed for \(prompt.storyId): \(error)")
                        return nil
                    }
                }
            }

            for await card in group {
                if let card {
                    await onCardGenerated(card)
                }
            }
        }
    }

    /// Round-robin interleave prompts by type for feed diversity.
    private func interleave(_ prompts: [StoryPrompt]) -> [StoryPrompt] {
        var byType: [StoryType: [StoryPrompt]] = [:]
        for prompt in prompts {
            byType[prompt.type, default: []].append(prompt)
        }

        // Priority order: trip, yearInReview, season, locationSpotlight
        let typeOrder: [StoryType] = [.trip, .yearInReview, .season, .locationSpotlight]
        var queues = typeOrder.compactMap { type -> (StoryType, [StoryPrompt])? in
            guard let items = byType[type], !items.isEmpty else { return nil }
            return (type, items)
        }

        var result: [StoryPrompt] = []
        var indices = Array(repeating: 0, count: queues.count)

        while result.count < prompts.count {
            var added = false
            for i in 0..<queues.count {
                if indices[i] < queues[i].1.count {
                    result.append(queues[i].1[indices[i]])
                    indices[i] += 1
                    added = true
                }
            }
            if !added { break }
        }

        return result
    }

    /// Total number of prompts to generate.
    var totalCount: Int { prompts.count }
}
