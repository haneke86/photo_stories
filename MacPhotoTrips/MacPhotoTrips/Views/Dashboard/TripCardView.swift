import SwiftUI

/// Glass card with expand/collapse showing stops — port of CSS .trip-card.
struct TripCardView: View {
    let trip: Trip
    let viewModel: DashboardViewModel
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card head: flag + text + chevron
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    // Flag
                    Text(viewModel.tripFlag(trip))
                        .font(.title)

                    // Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.tripLabel(trip))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)

                        HStack(spacing: 8) {
                            Text(viewModel.tripDateRange(trip))
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)

                            Text("\(trip.durationDays)d")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(DesignTokens.teal.opacity(0.12))
                                .foregroundStyle(DesignTokens.teal)
                                .clipShape(Capsule())
                        }

                        // Tagline (from LLM)
                        if let tagline = trip.tagline, !tagline.isEmpty {
                            Text(tagline)
                                .font(.caption)
                                .italic()
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }

                    Spacer()

                    // Chevron
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isExpanded ? DesignTokens.teal : DesignTokens.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .overlay(DesignTokens.glassBorder)

                    // Narrative (from LLM)
                    if let narrative = trip.narrative, !narrative.isEmpty {
                        Text(narrative)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .padding(.bottom, 4)
                    }

                    if trip.stops.count > 1 {
                        StopListView(stops: trip.stops, tripCountry: trip.countries.first ?? "")
                    } else if let stop = trip.stops.first, !stop.districts.isEmpty {
                        Text(stop.districts.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textTertiary)
                    }
                }
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    isExpanded ? DesignTokens.glassBorderHover : .clear,
                    lineWidth: 1
                )
        )
        .shadow(color: isExpanded ? .black.opacity(0.3) : .clear, radius: 16, y: 8)
    }
}
