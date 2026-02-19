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
                    MainTabView(timeline: timeline)
                }
            case .error(let message):
                ErrorView(message: message, onRetry: pipeline.start)
            }
        }
        .task { pipeline.checkPermission() }
    }
}

/// Tab container shown after pipeline completes.
private struct MainTabView: View {
    let timeline: Timeline

    @StateObject private var dashboardVM: DashboardViewModel
    @StateObject private var chatVM: ChatViewModel
    @State private var storiesLoading = false

    init(timeline: Timeline) {
        self.timeline = timeline
        _dashboardVM = StateObject(wrappedValue: DashboardViewModel(timeline: timeline))
        _chatVM = StateObject(wrappedValue: ChatViewModel(timeline: timeline))
    }

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(viewModel: dashboardVM)
            }
            .tabItem {
                Label("Trips", systemImage: "globe.europe.africa")
            }

            NavigationStack {
                ChatView(viewModel: chatVM)
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.text.bubble.right")
            }
        }
        .tint(DesignTokens.teal)
        .task {
            guard !storiesLoading else { return }
            storiesLoading = true
            if let provider = AnthropicDirectProvider() {
                let storyService = StoryService(provider: provider)
                if let narratives = await storyService.generateIfNeeded(timeline: timeline) {
                    dashboardVM.mergeNarratives(narratives)
                }
            }
            storiesLoading = false
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
