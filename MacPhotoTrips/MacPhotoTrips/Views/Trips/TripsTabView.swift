import SwiftUI

/// Trip list tab — compact rows grouped by year, tap opens detail sheet.
struct TripsTabView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var selectedTrip: Trip?
    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your Trips")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)

                        Text("\(viewModel.totalTrips) trips, \(viewModel.countriesCount) countries")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
                    .padding(.bottom, 24)

                    // Trip rows by year
                    ForEach(viewModel.yearGroups) { group in
                        // Year header
                        HStack(spacing: 8) {
                            Text(verbatim: "\(group.year)")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)

                            Text("\(group.trips.count) trips")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textTertiary)

                            VStack { Divider().overlay(DesignTokens.glassBorder) }
                        }
                        .padding(.vertical, 8)

                        // Compact trip rows
                        VStack(spacing: 8) {
                            ForEach(group.trips) { trip in
                                Button {
                                    selectedTrip = trip
                                } label: {
                                    TripRowView(trip: trip, viewModel: viewModel)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showShareSheet = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $selectedTrip) { trip in
            TripDetailView(trip: trip, viewModel: viewModel)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = TimelineStore.shareURL() {
                ShareSheet(items: [url])
            }
        }
    }
}
