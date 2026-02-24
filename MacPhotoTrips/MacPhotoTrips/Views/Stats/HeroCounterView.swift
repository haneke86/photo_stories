import SwiftUI

/// Dramatic animated hero section for the Insights page — large country counter
/// with secondary trip/days stats that fade in after the counter animation.
struct HeroCounterView: View {
    let countriesCount: Int
    let totalTrips: Int
    let totalDays: Int
    let sinceYear: String
    let homeCity: String

    @State private var showSubtitle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Header label
            Text("YOUR JOURNEY")
                .font(.system(size: 11, weight: .semibold))
                .tracking(4)
                .foregroundStyle(DesignTokens.textTertiary)

            // 2. Main counter
            HStack(alignment: .firstTextBaseline) {
                AnimatedCounter(
                    target: countriesCount,
                    font: .system(size: 72, weight: .bold, design: .rounded),
                    color: AnyShapeStyle(DesignTokens.gradient),
                    duration: 1.0
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("countries")
                        .font(.title.weight(.light))
                        .foregroundStyle(.white.opacity(0.85))

                    Text("explored since \(sinceYear)")
                        .font(.title3.weight(.light))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            // 3. Secondary stats
            HStack(spacing: 6) {
                Label("\(totalTrips) trips", systemImage: "airplane")
                Text("·")
                Label("\(totalDays) days", systemImage: "calendar")
                Text("·")
                Label("from \(homeCity)", systemImage: "house")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(DesignTokens.textSecondary)
            .opacity(showSubtitle ? 1 : 0)
            .offset(y: showSubtitle ? 0 : 8)
            .animation(.easeOut(duration: 0.5).delay(0.8), value: showSubtitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 48)
        .padding(.bottom, 16)
        .onAppear {
            showSubtitle = true
        }
    }
}
