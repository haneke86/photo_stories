import SwiftUI

/// 4-page onboarding carousel: features → AI → privacy → sign-in.
struct OnboardingCarouselView: View {
    @ObservedObject var authVM: AuthViewModel
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    // Page 1: Travel Timeline
                    OnboardingPageView(
                        icon: "globe.europe.africa",
                        headline: "Your Travel Timeline",
                        bodyText: "We read location data from your photos to auto-detect trips and build a beautiful travel timeline.",
                        bullets: [
                            ("map.fill", "Auto-detect trips from geotagged photos"),
                            ("mappin.and.ellipse", "Identify cities and countries visited"),
                            ("chart.bar.fill", "Year-by-year travel statistics"),
                        ]
                    )
                    .tag(0)

                    // Page 2: AI Stories
                    OnboardingPageView(
                        icon: "book.pages.fill",
                        headline: "AI-Powered Trip Stories",
                        bodyText: "Get rich narratives about your journeys and ask questions about your travel history.",
                        bullets: [
                            ("text.book.closed.fill", "Generated stories for each trip"),
                            ("bubble.left.and.text.bubble.right.fill", "Chat with your travel history"),
                            ("globe.desk.fill", "Interactive map of everywhere you've been"),
                        ]
                    )
                    .tag(1)

                    // Page 3: Privacy
                    privacyPage
                        .tag(2)

                    // Page 4: Sign In
                    signInPage
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                // Bottom navigation
                bottomBar
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Privacy Page (custom layout with checkmarks)

    private var privacyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 72))
                .foregroundStyle(DesignTokens.gradient)

            VStack(spacing: 8) {
                Text("Your Privacy Matters")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text("We take your privacy seriously.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                PrivacyRow("We only read location data — never your photo or video content")
                PrivacyRow("Trip detection uses location metadata from your photos")
                PrivacyRow("AI features send only city names and dates via encrypted connection")
                PrivacyRow("No personal information is stored on our servers")
            }
            .padding(.horizontal, 32)

            Text("Your photos and media content are never accessed or uploaded.")
                .font(.caption)
                .foregroundStyle(DesignTokens.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Sign In Page

    private var signInPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 72))
                .foregroundStyle(DesignTokens.gradient)

            VStack(spacing: 8) {
                Text("Let's Get Started")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text("Sign in to unlock AI-powered stories and chat.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
            }

            Spacer()

            // Sign in with Apple button
            Button {
                Task {
                    await authVM.signIn()
                    if authVM.isAuthenticated {
                        hasCompletedOnboarding = true
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                        .font(.title3)
                    Text("Sign in with Apple")
                        .font(.title3.weight(.medium))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(.white)
                .clipShape(Capsule())
            }
            .padding(.horizontal, 40)
            .disabled(authVM.isLoading)

            if authVM.isLoading {
                ProgressView()
                    .tint(DesignTokens.teal)
            }

            if let error = authVM.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Text("By continuing, you agree to our Privacy Policy")
                .font(.caption)
                .foregroundStyle(DesignTokens.textTertiary)

            Spacer()
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if currentPage < 3 {
                Button("Skip") {
                    withAnimation { currentPage = 3 }
                }
                .foregroundStyle(DesignTokens.textSecondary)

                Spacer()

                Button {
                    withAnimation { currentPage += 1 }
                } label: {
                    Text("Next")
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignTokens.teal)
                }
            } else {
                Spacer()
            }
        }
        .frame(height: 44)
    }
}

// MARK: - Privacy Row

private struct PrivacyRow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }
}
