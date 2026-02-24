import SwiftUI

/// Photo library access request screen — styled to match dark onboarding theme.
struct PermissionView: View {
    let onRequest: () -> Void

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(DesignTokens.gradient)

                VStack(spacing: 8) {
                    Text("Your Travel Story")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                    Text("MacPhotoTrips reads your photo library to discover your trips and build a beautiful travel timeline.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .padding(.horizontal, 32)
                }

                VStack(alignment: .leading, spacing: 14) {
                    PermissionFeatureRow(icon: "map.fill", text: "Detect trips from geotagged photos")
                    PermissionFeatureRow(icon: "building.2.fill", text: "Auto-identify cities and countries")
                    PermissionFeatureRow(icon: "clock.fill", text: "Build a timeline of your travels")
                }
                .padding(.horizontal, 40)

                Spacer()

                Button(action: onRequest) {
                    Text("Allow Photo Access")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DesignTokens.teal)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 32)

                VStack(spacing: 4) {
                    Text("We only read the ")
                        + Text("where").fontWeight(.semibold)
                        + Text(" and ")
                        + Text("when").fontWeight(.semibold)
                        + Text(" of your photos — never the content.")
                    Text("Your photos and media never leave your device.")
                }
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(DesignTokens.textTertiary)
                .padding(.horizontal, 32)

                Spacer().frame(height: 32)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct PermissionFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(DesignTokens.teal)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }
}
