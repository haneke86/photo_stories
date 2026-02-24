import SwiftUI

/// Redesigned Insights page — Apple Year-in-Review style with
/// animated counters, stat rings, travel records, and social sharing.
struct StatsTabView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: 0) {
                    // Section 1: Hero Counter
                    HeroCounterView(
                        countriesCount: viewModel.countriesCount,
                        totalTrips: viewModel.totalTrips,
                        totalDays: viewModel.totalDays,
                        sinceYear: viewModel.sinceYear,
                        homeCity: viewModel.homeCity
                    )

                    // Section 2: Stat Rings
                    StatRingsView(
                        trips: viewModel.totalTrips,
                        days: viewModel.totalDays,
                        cities: viewModel.totalCities,
                        photos: viewModel.totalPhotos,
                        avgDays: viewModel.averageTripDuration
                    )
                    .padding(.top, 16)

                    // Section 3: Timeline bar (kept from original)
                    TimelineBarView(years: viewModel.timelineYears)
                        .padding(.top, 32)

                    // Section 4: Travel Records
                    TravelRecordsView(viewModel: viewModel)
                        .padding(.top, 32)

                    // Section 5: Country Leaderboard
                    CountryLeaderboardView(
                        countries: viewModel.countryFrequency,
                        totalCountries: viewModel.countriesCount
                    )
                    .padding(.top, 32)

                    // Section 6: Year-over-Year Growth
                    YearGrowthView(
                        tripsPerYear: viewModel.tripsPerYear,
                        daysPerYear: viewModel.daysPerYear,
                        busiestYear: viewModel.busiestYear
                    )
                    .padding(.top, 32)

                    // Section 7: Share CTA
                    InsightsShareButton(viewModel: viewModel)
                        .padding(.top, 40)

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
}
