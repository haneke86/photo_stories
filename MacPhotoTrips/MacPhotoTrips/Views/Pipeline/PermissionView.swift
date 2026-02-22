import SwiftUI

/// Photo library access request screen.
struct PermissionView: View {
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "globe.americas.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [DesignTokens.teal, DesignTokens.lavender],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Text("Your Travel Story")
                    .font(.title.weight(.bold))
                Text("MacPhotoTrips reads your photo library to discover your trips and build a beautiful travel timeline.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "map.fill", text: "Detect trips from geotagged photos")
                FeatureRow(icon: "building.2.fill", text: "Auto-identify cities and countries")
                FeatureRow(icon: "clock.fill", text: "Build a timeline of your travels")
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 16)

            Spacer()

            Button(action: onRequest) {
                Text("Allow Photo Access")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.teal)
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
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 32)

            Spacer().frame(height: 32)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(DesignTokens.teal)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
