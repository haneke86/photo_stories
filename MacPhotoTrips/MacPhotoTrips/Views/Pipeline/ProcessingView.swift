import SwiftUI

/// Progress screen during extraction + geocoding.
struct ProcessingView: View {
    @ObservedObject var viewModel: PipelineViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated globe
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [DesignTokens.teal, DesignTokens.lavender, DesignTokens.rose],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: 8) {
                Text(viewModel.currentStep.rawValue)
                    .font(.title3.weight(.semibold))

                Text(viewModel.progressDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if viewModel.currentStep == .geocoding {
                VStack(spacing: 8) {
                    ProgressView(value: viewModel.progress)
                        .tint(DesignTokens.teal)
                        .padding(.horizontal, 48)

                    Text("\(Int(viewModel.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            } else {
                ProgressView()
                    .controlSize(.large)
            }

            Spacer()

            Text("This may take a few minutes on first run.\nSubsequent runs will be much faster.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 32)
        }
    }
}
