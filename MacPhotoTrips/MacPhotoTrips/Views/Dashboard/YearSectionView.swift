import SwiftUI

/// Year header + trip cards — port of CSS .year-header + .year-cards.
struct YearSectionView: View {
    let group: DashboardViewModel.YearGroup
    let viewModel: DashboardViewModel

    var body: some View {
        Section {
            ForEach(group.trips) { trip in
                TripCardView(trip: trip, viewModel: viewModel)
            }
        } header: {
            // Sticky year header
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(group.year)")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("\(group.trips.count) trips")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textTertiary)

                    VStack { Divider().overlay(DesignTokens.glassBorder) }
                }

                if let narrative = group.yearNarrative, !narrative.isEmpty {
                    Text(narrative)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 8)
            .background(
                DesignTokens.bg.opacity(0.7)
                    .background(.ultraThinMaterial.opacity(0.3))
                    .ignoresSafeArea()
            )
        }
    }
}

/// Timeline bar visualization — port of CSS .tl-track.
struct TimelineBarView: View {
    let years: [DashboardViewModel.TimelineYear]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TIMELINE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(DesignTokens.textTertiary)
                .padding(.bottom, 12)

            VStack(spacing: 6) {
                ForEach(years) { year in
                    HStack(spacing: 0) {
                        Text("\(year.year)")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .frame(width: 40, alignment: .trailing)
                            .padding(.trailing, 10)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // Background bar
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.02))

                                // Trip blocks
                                ForEach(year.blocks) { block in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(DesignTokens.gradient)
                                        .opacity(0.75)
                                        .frame(
                                            width: max(4, geo.size.width * block.widthPercent / 100),
                                            height: geo.size.height - 6
                                        )
                                        .offset(
                                            x: geo.size.width * block.startPercent / 100,
                                            y: 3
                                        )
                                }
                            }
                        }
                        .frame(height: 24)
                    }
                }

                // Month labels
                HStack(spacing: 0) {
                    Color.clear.frame(width: 50)
                    ForEach(["J","F","M","A","M","J","J","A","S","O","N","D"], id: \.self) { m in
                        Text(m)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(DesignTokens.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(24)
        .glassCard()
    }
}
