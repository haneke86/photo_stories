import SwiftUI

/// Combined Trips + Map tab with toolbar toggle between list and map modes.
struct ExploreTabView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var pipeline: PipelineViewModel
    @State private var showMap = false
    @State private var selectedTrip: Trip?
    @State private var showShareSheet = false

    var body: some View {
        Group {
            if showMap {
                mapMode
            } else {
                listMode
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showMap)
        .navigationTitle("Explore")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showMap.toggle()
                    } label: {
                        Image(systemName: showMap ? "list.bullet" : "map")
                    }

                    if !showMap {
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
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

    // MARK: - List Mode

    private var listMode: some View {
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
        .refreshable {
            await pipeline.incrementalRefresh()
        }
    }

    // MARK: - Map Mode

    private var mapMode: some View {
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
    }
}
