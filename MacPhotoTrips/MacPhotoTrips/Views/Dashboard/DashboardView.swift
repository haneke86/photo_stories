import SwiftUI

/// Legacy monolithic dashboard — content now distributed to Trips/Stories/Map/Stats tabs.
/// Kept for reference; no longer instantiated.
struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: 0) {
                    HeroView(viewModel: viewModel)
                    StatsStripView(viewModel: viewModel)
                        .padding(.top, 24)

                    TimelineBarView(years: viewModel.timelineYears)
                        .padding(.top, 40)

                    TripMapView(annotations: viewModel.allStopAnnotations)
                        .padding(.top, 24)

                    ForEach(viewModel.yearGroups) { group in
                        YearSectionView(group: group, viewModel: viewModel)
                    }
                    .padding(.top, 40)

                    Text("Built from your Photos library")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textTertiary)
                        .padding(.vertical, 40)
                }
                .padding(.horizontal, 16)
            }
        }
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = TimelineStore.shareURL() {
                ShareSheet(items: [url])
            }
        }
    }
}
