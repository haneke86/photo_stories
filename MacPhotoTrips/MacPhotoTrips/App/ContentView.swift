import SwiftUI
import Photos

/// Root view: permission gate → processing → dashboard.
struct ContentView: View {
    @StateObject private var pipeline = PipelineViewModel()

    var body: some View {
        Group {
            switch pipeline.state {
            case .needsPermission:
                PermissionView(onRequest: pipeline.requestPermission)
            case .denied:
                PermissionDeniedView()
            case .processing:
                ProcessingView(viewModel: pipeline)
            case .ready:
                if let timeline = pipeline.timeline {
                    MainTabView(timeline: timeline, pipeline: pipeline)
                }
            case .error(let message):
                ErrorView(message: message, onRetry: pipeline.start)
            }
        }
        .task { pipeline.checkPermission() }
    }
}

/// Tab container — 5 tabs: Trips, Stories, Map, Stats, Chat.
private struct MainTabView: View {
    let timeline: Timeline
    @ObservedObject var pipeline: PipelineViewModel

    @StateObject private var dashboardVM: DashboardViewModel
    @StateObject private var feedVM: StoryFeedViewModel
    @StateObject private var chatVM: ChatViewModel

    init(timeline: Timeline, pipeline: PipelineViewModel) {
        self.timeline = timeline
        self.pipeline = pipeline
        let dvm = DashboardViewModel(timeline: timeline)
        _dashboardVM = StateObject(wrappedValue: dvm)
        _feedVM = StateObject(wrappedValue: StoryFeedViewModel(pipeline: pipeline))
        _chatVM = StateObject(wrappedValue: ChatViewModel(timeline: timeline))
    }

    var body: some View {
        TabView {
            NavigationStack {
                TripsTabView(viewModel: dashboardVM)
            }
            .tabItem {
                Label("Trips", systemImage: "globe.europe.africa")
            }

            StoryFeedView(feedVM: feedVM, dashboardVM: dashboardVM)
                .tabItem {
                    Label("Stories", systemImage: "book.pages")
                }

            MapTabView(viewModel: dashboardVM)
                .tabItem {
                    Label("Map", systemImage: "map")
                }

            NavigationStack {
                StatsTabView(viewModel: dashboardVM)
            }
            .tabItem {
                Label("Stats", systemImage: "chart.bar.xaxis")
            }

            NavigationStack {
                ChatView(viewModel: chatVM)
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.text.bubble.right")
            }
        }
        .tint(DesignTokens.teal)
        .onReceive(pipeline.$timeline) { newTimeline in
            // Silently refresh dashboard when background refinement completes.
            guard let newTimeline else { return }
            let oldTrips = dashboardVM.timeline.trips
            let newTrips = newTimeline.trips
            let changed = oldTrips.count != newTrips.count
                || oldTrips.map(\.id) != newTrips.map(\.id)
                || oldTrips.map(\.cities) != newTrips.map(\.cities)
            guard changed else { return }
            dashboardVM.updateTimeline(newTimeline)
        }
    }
}

// MARK: - Helper Views

private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Photo Access Required")
                .font(.title2.weight(.semibold))
            Text("Open Settings and grant photo library access to see your travel timeline.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

private struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.title2.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
