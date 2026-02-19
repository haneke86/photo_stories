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
                    let vm = DashboardViewModel(timeline: timeline)
                    DashboardView(viewModel: vm)
                        .task {
                            if let narratives = pipeline.narrativeResult {
                                vm.mergeNarratives(narratives)
                            }
                        }
                }
            case .error(let message):
                ErrorView(message: message, onRetry: pipeline.start)
            }
        }
        .task { pipeline.checkPermission() }
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
