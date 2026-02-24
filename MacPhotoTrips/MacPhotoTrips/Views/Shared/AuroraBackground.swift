import SwiftUI

/// Aurora mesh gradient background — port of CSS .aurora.
/// Shared across Trips, Stories, and Stats tabs.
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            DesignTokens.bg.ignoresSafeArea()

            // Teal blob top-left
            Circle()
                .fill(DesignTokens.teal.opacity(0.12))
                .frame(width: 400, height: 300)
                .blur(radius: 100)
                .offset(x: -100, y: -200)

            // Lavender blob bottom-right
            Circle()
                .fill(DesignTokens.lavender.opacity(0.10))
                .frame(width: 350, height: 350)
                .blur(radius: 100)
                .offset(x: 100, y: 300)

            // Rose blob center
            Circle()
                .fill(DesignTokens.rose.opacity(0.06))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
        }
        .ignoresSafeArea()
    }
}
