import SwiftUI
import Photos

/// Root view: onboarding gate → auth gate → permission gate → processing → dashboard.
struct ContentView: View {
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var pipeline = PipelineViewModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingCarouselView(
                    authVM: authVM,
                    hasCompletedOnboarding: $hasCompletedOnboarding
                )
            } else if !authVM.isAuthenticated {
                LoginView(authVM: authVM)
            } else {
                authenticatedContent
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        Group {
            switch pipeline.state {
            case .needsPermission:
                PermissionView(onRequest: pipeline.requestPermission)
            case .denied:
                PermissionDeniedView()
            case .limitedNoPhotos:
                LimitedAccessView()
            case .processing:
                ProcessingView(viewModel: pipeline)
            case .ready:
                if let timeline = pipeline.timeline {
                    MainTabView(
                        timeline: timeline,
                        pipeline: pipeline,
                        authVM: authVM
                    )
                }
            case .error(let message):
                ErrorView(message: message, onRetry: pipeline.start)
            }
        }
        .task { pipeline.checkPermission() }
    }
}

/// Tab container — 5 tabs: Explore, Stories, Insights, Chat, Settings.
private struct MainTabView: View {
    let timeline: Timeline
    @ObservedObject var pipeline: PipelineViewModel
    @ObservedObject var authVM: AuthViewModel

    @StateObject private var dashboardVM: DashboardViewModel
    @StateObject private var feedVM: StoryFeedViewModel
    @StateObject private var chatVM: ChatViewModel
    @StateObject private var settingsVM: SettingsViewModel

    init(timeline: Timeline, pipeline: PipelineViewModel, authVM: AuthViewModel) {
        self.timeline = timeline
        self.pipeline = pipeline
        self.authVM = authVM
        let provider = BackendProvider(authService: authVM.authService)
        let dvm = DashboardViewModel(timeline: timeline)
        _dashboardVM = StateObject(wrappedValue: dvm)
        _feedVM = StateObject(wrappedValue: StoryFeedViewModel(pipeline: pipeline, provider: provider))
        _chatVM = StateObject(wrappedValue: ChatViewModel(timeline: timeline, provider: provider))
        _settingsVM = StateObject(wrappedValue: SettingsViewModel(provider: provider, authService: authVM.authService))
    }

    var body: some View {
        TabView {
            NavigationStack {
                ExploreTabView(viewModel: dashboardVM, pipeline: pipeline)
            }
            .tabItem {
                Label("Explore", systemImage: "globe.europe.africa")
            }

            StoryFeedView(feedVM: feedVM, dashboardVM: dashboardVM, authVM: authVM)
                .tabItem {
                    Label("Stories", systemImage: "book.pages")
                }

            NavigationStack {
                StatsTabView(viewModel: dashboardVM)
            }
            .tabItem {
                Label("Insights", systemImage: "chart.bar.xaxis")
            }

            NavigationStack {
                ChatView(viewModel: chatVM)
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.text.bubble.right")
            }

            NavigationStack {
                SettingsView(authVM: authVM, settingsVM: settingsVM)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(DesignTokens.teal)
        .onReceive(pipeline.$timeline) { newTimeline in
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

private struct LimitedAccessView: View {
    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 64))
                    .foregroundStyle(DesignTokens.gradient)

                VStack(spacing: 8) {
                    Text("No Geotagged Photos Selected")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("You granted limited access, but none of the selected photos have location data. To build your travel timeline, please allow full access or select photos taken during your trips.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 12) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open Settings")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(DesignTokens.teal)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 32)

                    Text("Change photo access to \"Full Access\" or select geotagged photos.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct PermissionDeniedView: View {
    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 64))
                    .foregroundStyle(DesignTokens.gradient)

                VStack(spacing: 8) {
                    Text("Photo Access Required")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("MacPhotoTrips needs photo library access to discover your trips. Please grant access in Settings.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .padding(.horizontal, 32)
                }

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DesignTokens.teal)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)

                VStack(spacing: 8) {
                    Text("Something Went Wrong")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .padding(.horizontal, 32)
                }

                Button(action: onRetry) {
                    Text("Try Again")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DesignTokens.teal)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}
