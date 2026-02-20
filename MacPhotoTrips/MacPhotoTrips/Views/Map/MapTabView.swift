import SwiftUI

/// Full-screen interactive satellite map tab with tappable annotations.
struct MapTabView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var selectedTrip: Trip?

    var body: some View {
        ZStack(alignment: .top) {
            InteractiveTripMapView(
                annotations: viewModel.allStopAnnotations
            ) { annotation in
                if let trip = viewModel.trip(byId: annotation.tripId) {
                    selectedTrip = trip
                }
            }
            .ignoresSafeArea(edges: .bottom)

            // Floating stats pill
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.teal)

                Text("\(viewModel.allStopAnnotations.count) stops")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)

                Text("·")
                    .foregroundStyle(DesignTokens.textTertiary)

                Text("\(viewModel.countriesCount) countries")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.3))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(DesignTokens.glassBorder, lineWidth: 1))
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selectedTrip) { trip in
            TripDetailView(trip: trip, viewModel: viewModel)
        }
    }
}
