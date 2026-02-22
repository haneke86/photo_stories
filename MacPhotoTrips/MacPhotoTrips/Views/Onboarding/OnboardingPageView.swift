import SwiftUI

/// Reusable onboarding page with icon, headline, body, and bullet points.
struct OnboardingPageView: View {
    let icon: String
    let headline: String
    let bodyText: String
    let bullets: [(icon: String, text: String)]

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
    }
}
