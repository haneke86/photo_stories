import SwiftUI

/// Full-screen trip detail sheet — shared by Trips tab and Map tab.
/// Generates a story on-the-fly if one doesn't exist yet.
struct TripDetailView: View {
    let trip: Trip
    let viewModel: DashboardViewModel

    @State private var tagline: String?
    @State private var narrative: String?
    @State private var isGenerating = false

    /// Resolved tagline: local state (from on-demand gen) or trip's existing one.
    private var displayTagline: String? {
        tagline ?? trip.tagline
    }

    /// Resolved narrative: local state (from on-demand gen) or trip's existing one.
    private var displayNarrative: String? {
        narrative ?? trip.narrative
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Grab handle
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 36, height: 5)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                    // Type badge
                    HStack(spacing: 6) {
                        Image(systemName: "airplane")
                            .font(.caption2.weight(.semibold))
                        Text("TRIP")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.5)
                    }
                    .foregroundStyle(DesignTokens.teal)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DesignTokens.teal.opacity(0.12))
                    .clipShape(Capsule())

                    // Flags row
                    Text(trip.countries.map { CountryFlags.flag(forCountry: $0) }.joined(separator: " "))
                        .font(.largeTitle)

                    // City label
                    Text(viewModel.tripLabel(trip))
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)

                    // Tagline
                    if let tagline = displayTagline, !tagline.isEmpty {
                        Text(tagline)
                            .font(.title3)
                            .italic()
                            .foregroundStyle(DesignTokens.teal.opacity(0.8))
                    }

                    // Date range + duration pill
                    HStack(spacing: 10) {
                        Text(viewModel.tripDateRange(trip))
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.textSecondary)

                        Text("\(trip.durationDays) days")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(DesignTokens.teal.opacity(0.15))
                            .foregroundStyle(DesignTokens.teal)
                            .clipShape(Capsule())
                    }

                    // Country pills (if multi-country)
                    if trip.countries.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(trip.countries, id: \.self) { country in
                                HStack(spacing: 4) {
                                    Text(CountryFlags.flag(forCountry: country))
                                        .font(.caption2)
                                    Text(country)
                                        .font(.caption2)
                                        .foregroundStyle(DesignTokens.textSecondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.04))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(DesignTokens.glassBorder, lineWidth: 1))
                            }
                        }
                    }

                    Divider()
                        .overlay(DesignTokens.glassBorder)

                    // Narrative section: show content, loading, or nothing
                    if let narrative = displayNarrative, !narrative.isEmpty {
                        Text(narrative)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if isGenerating {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(DesignTokens.teal)
                            Text("Writing your story...")
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                        .padding(.vertical, 8)
                    }

                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .task { await generateIfNeeded() }
    }

    // MARK: - On-Demand Generation

    private func generateIfNeeded() async {
        // Already has a narrative — nothing to do
        guard trip.narrative == nil || trip.narrative?.isEmpty == true else { return }

        guard let provider = AnthropicDirectProvider() else { return }

        isGenerating = true

        // Build prompt for this specific trip
        let prompts = StoryPromptBuilder.buildAll(from: viewModel.timeline)
        guard let prompt = prompts.first(where: { $0.storyId == "trip-\(trip.id)" }) else {
            isGenerating = false
            return
        }

        do {
            let response = try await provider.generateSingleStory(
                systemPrompt: prompt.systemPrompt,
                userMessage: prompt.userMessage
            )

            tagline = response.tagline
            narrative = response.narrative

            // Persist back to the view model so it survives closing the sheet
            viewModel.setTripNarrative(
                tripId: trip.id,
                narrative: response.narrative,
                tagline: response.tagline
            )

            // Also save to the story catalog for cross-session persistence
            let catalog = StoryCatalog()
            let hash = StoryCatalog.hash(for: viewModel.timeline)
            let card = StoryCard(
                id: "trip-\(trip.id)",
                type: .trip,
                title: response.title,
                tagline: response.tagline,
                narrative: response.narrative,
                generatedAt: Date(),
                flags: prompt.flags,
                countries: prompt.countries,
                dateLabel: prompt.dateLabel,
                durationLabel: prompt.durationLabel,
                associatedTripIds: [trip.id],
                timelineHash: hash
            )
            await catalog.save(card)
        } catch {
            print("On-demand story generation failed: \(error)")
        }

        isGenerating = false
    }
}
