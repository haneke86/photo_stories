import SwiftUI

/// Progress screen during extraction + geocoding.
/// Dark-themed with AuroraBackground, shows ETA and keep-open guidance.
struct ProcessingView: View {
    @ObservedObject var viewModel: PipelineViewModel

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 24) {
                Spacer()

                // Animated globe
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(DesignTokens.gradient)
                    .symbolEffect(.pulse, options: .repeating)

                VStack(spacing: 8) {
                    Text(viewModel.currentStep.rawValue)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(viewModel.progressDetail)
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .multilineTextAlignment(.center)
                }

                if viewModel.currentStep == .geocoding {
                    VStack(spacing: 8) {
                        ProgressView(value: viewModel.progress)
                            .tint(DesignTokens.teal)
                            .padding(.horizontal, 48)

                        HStack(spacing: 16) {
                            Text("\(Int(viewModel.progress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(DesignTokens.textTertiary)

                            if let eta = viewModel.estimatedSecondsRemaining, eta > 0 {
                                Text("~\(formattedETA(eta)) remaining")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(DesignTokens.textTertiary)
                            }
                        }
                    }
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(DesignTokens.teal)
                }

                Spacer()

                // Keep-open guidance
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone.and.arrow.forward")
                            .foregroundStyle(DesignTokens.teal)
                        Text("Please keep the app open")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }

                    Text("First-time setup geocodes your photo locations.\nThe screen will stay on — no need to touch anything.\nFuture launches will be instant.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer().frame(height: 32)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func formattedETA(_ seconds: Int) -> String {
        if seconds >= 60 {
            let min = seconds / 60
            let sec = seconds % 60
            return sec > 0 ? "\(min)m \(sec)s" : "\(min)m"
        }
        return "\(seconds)s"
    }
}
