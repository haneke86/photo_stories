import SwiftUI

/// Infographic-style statistics page — aggregated travel data.
struct StatsTabView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: 0) {
                    // Hero
                    HeroView(viewModel: viewModel)

                    // Core stats strip
                    StatsStripView(viewModel: viewModel)
                        .padding(.top, 24)

                    // Extended stats row
                    extendedStatsRow
                        .padding(.top, 2)

                    // Timeline bar chart
                    TimelineBarView(years: viewModel.timelineYears)
                        .padding(.top, 32)

                    // Highlight cards
                    highlightCards
                        .padding(.top, 32)

                    // Country breakdown bar chart
                    countryBreakdown
                        .padding(.top, 32)

                    // Year comparison charts
                    yearComparison
                        .padding(.top, 32)

                    // Footer
                    Text("Built from your Photos library")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textTertiary)
                        .padding(.vertical, 40)
                }
                .padding(.horizontal, 16)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Extended Stats Row

    private var extendedStatsRow: some View {
        HStack(spacing: 2) {
            extendedStatCell(value: "\(viewModel.totalCities)", label: "CITIES")
            extendedStatCell(value: "\(viewModel.totalPhotos)", label: "PHOTOS")
            extendedStatCell(
                value: String(format: "%.0f", viewModel.averageTripDuration),
                label: "AVG DAYS"
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func extendedStatCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(DesignTokens.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial.opacity(0.5))
        .background(Color.white.opacity(0.04))
    }

    // MARK: - Highlight Cards

    private var highlightCards: some View {
        VStack(spacing: 12) {
            Text("HIGHLIGHTS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(DesignTokens.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                // Longest trip
                if let longest = viewModel.longestTrip {
                    highlightCard(
                        icon: "airplane",
                        value: "\(longest.durationDays) days",
                        detail: viewModel.tripLabel(longest),
                        label: "Longest Trip"
                    )
                }

                // Most visited country
                if let topCountry = viewModel.countryFrequency.first {
                    highlightCard(
                        icon: "flag.fill",
                        value: CountryFlags.flag(forCountry: topCountry.country),
                        detail: "\(topCountry.country) · \(topCountry.count) trips",
                        label: "Most Visited"
                    )
                }

                // Busiest year
                if let busiest = viewModel.busiestYear {
                    highlightCard(
                        icon: "calendar",
                        value: "\(busiest.year)",
                        detail: "\(busiest.tripsCount) trips · \(busiest.daysAbroad)d",
                        label: "Busiest Year"
                    )
                }
            }
        }
    }

    private func highlightCard(icon: String, value: String, detail: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DesignTokens.teal)

            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(DesignTokens.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)

            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .tracking(1)
                .foregroundStyle(DesignTokens.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .glassCard()
    }

    // MARK: - Country Breakdown

    private var countryBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COUNTRIES BY TRIPS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(DesignTokens.textTertiary)

            let top10 = Array(viewModel.countryFrequency.prefix(10))
            let maxCount = top10.first?.count ?? 1

            ForEach(Array(top10.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 10) {
                    Text(CountryFlags.flag(forCountry: item.country))
                        .font(.caption)
                        .frame(width: 24)

                    Text(item.country)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(width: 90, alignment: .leading)
                        .lineLimit(1)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [DesignTokens.teal, DesignTokens.teal.opacity(0.5)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(item.count) / CGFloat(maxCount))
                    }
                    .frame(height: 16)

                    Text("\(item.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(width: 24, alignment: .trailing)
                }
                .frame(height: 22)
            }
        }
        .padding(24)
        .glassCard()
    }

    // MARK: - Year Comparison

    private var yearComparison: some View {
        VStack(spacing: 16) {
            miniBarChart(
                title: "TRIPS PER YEAR",
                data: viewModel.tripsPerYear.map { (label: "\($0.year)", value: $0.count) },
                color: DesignTokens.teal
            )

            miniBarChart(
                title: "DAYS ABROAD PER YEAR",
                data: viewModel.daysPerYear.map { (label: "\($0.year)", value: $0.days) },
                color: DesignTokens.lavender
            )
        }
    }

    private func miniBarChart(title: String, data: [(label: String, value: Int)], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(DesignTokens.textTertiary)

            let maxVal = data.map(\.value).max() ?? 1

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 4) {
                        Text("\(item.value)")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(DesignTokens.textSecondary)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.7))
                            .frame(height: max(4, CGFloat(item.value) / CGFloat(maxVal) * 80))

                        Text(String(item.label.suffix(2)))
                            .font(.system(size: 9))
                            .foregroundStyle(DesignTokens.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110)
        }
        .padding(24)
        .glassCard()
    }
}
