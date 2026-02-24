import SwiftUI
import AuthenticationServices

/// Sign-in screen for returning users (post-onboarding).
struct LoginView: View {
    @ObservedObject var authVM: AuthViewModel

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 24) {
                Spacer()

                // App icon
                Image(systemName: "globe.europe.africa")
                    .font(.system(size: 72))
                    .foregroundStyle(DesignTokens.gradient)

                // Title
                Text("MacPhotoTrips")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)

                // Tagline
                Text("Welcome back")
                    .font(.title3)
                    .foregroundStyle(DesignTokens.textSecondary)

                Spacer()

                // Sign in with Apple (via Cognito hosted UI)
                Button {
                    Task { await authVM.signIn() }
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

                // Privacy note
                Text("Your photos and data stay on your device")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textTertiary)
                    .padding(.bottom, 16)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}
