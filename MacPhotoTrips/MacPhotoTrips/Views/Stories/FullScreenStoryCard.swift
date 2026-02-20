import SwiftUI

/// Full-screen story card for the vertical-swipe feed.
struct FullScreenStoryCard: View {
    let card: StoryCard

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Spacer()
                        .frame(height: 40)

                    // Type badge
                    typeBadge

                    // Flags row
                    if !card.flags.isEmpty {
                        Text(card.flags.joined(separator: " "))
                            .font(.largeTitle)
                    }

                    // Title
                    Text(card.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)

                    // Tagline
                    if !card.tagline.isEmpty {
                        Text(card.tagline)
                            .font(.title3)
                            .italic()
                            .foregroundStyle(accentColor.opacity(0.8))
                    }

                    // Date + duration
                    HStack(spacing: 10) {
                        Text(card.dateLabel)
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.textSecondary)

                        if let duration = card.durationLabel {
                            Text(duration)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(accentColor.opacity(0.15))
                                .foregroundStyle(accentColor)
                                .clipShape(Capsule())
                        }
                    }

                    // Country pills (if multi-country)
                    if card.countries.count > 1 {
                        countryPills
                    }

                    Divider()
                        .overlay(DesignTokens.glassBorder)

                    // Narrative body
                    Text(card.narrative)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                        .frame(height: 60)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Type Badge

    private var typeBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: card.type.icon)
                .font(.caption2.weight(.semibold))
            Text(card.type.label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
        }
        .foregroundStyle(accentColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(accentColor.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Country Pills

    private var countryPills: some View {
        HStack(spacing: 6) {
            ForEach(card.countries, id: \.self) { country in
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
        .padding(.top, 4)
    }

    // MARK: - Accent Color per Type

    private var accentColor: Color {
        switch card.type {
        case .trip: return DesignTokens.teal
        case .yearInReview: return DesignTokens.lavender
        case .season: return DesignTokens.rose
        case .locationSpotlight: return .orange
        }
    }
}
