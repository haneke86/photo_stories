import SwiftUI

/// Reusable onboarding page with icon, headline, body, and bullet points.
/// Optionally displays a background image layered behind the content.
struct OnboardingPageView: View {
    let icon: String
    let headline: String
    let bodyText: String
    let bullets: [(icon: String, text: String)]
    var backgroundImage: String? = nil

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 72))
                .foregroundStyle(DesignTokens.gradient)

            VStack(spacing: 8) {
                Text(headline)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text(bodyText)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .padding(.horizontal, 32)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(spacing: 12) {
                        Image(systemName: bullet.icon)
                            .foregroundStyle(DesignTokens.teal)
                            .frame(width: 24)
                        Text(bullet.text)
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
        .background {
            OnboardingImageBackground(imageName: backgroundImage)
        }
    }
}

// MARK: - Background Image Layer

/// Layered background for onboarding pages: photo image at reduced opacity
/// with a radial gradient overlay to keep the center dark for text legibility.
/// Gracefully shows nothing if the image asset is missing.
struct OnboardingImageBackground: View {
    let imageName: String?

    var body: some View {
        if let name = imageName, UIImage(named: name) != nil {
            GeometryReader { geo in
                ZStack {
                    Image(name)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(0.4)

                    // Radial gradient: dark center for text, lighter edges for image detail
                    RadialGradient(
                        colors: [
                            DesignTokens.bg.opacity(0.85),
                            DesignTokens.bg.opacity(0.4),
                            DesignTokens.bg.opacity(0.6),
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: UIScreen.main.bounds.height * 0.5
                    )

                    // Top & bottom edge fade to base color
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [DesignTokens.bg, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: geo.size.height * 0.15)

                        Spacer()

                        LinearGradient(
                            colors: [.clear, DesignTokens.bg],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: geo.size.height * 0.2)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
}
