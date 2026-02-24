import SwiftUI

/// Animated country leaderboard with medal indicators and horizontal bar chart.
struct CountryLeaderboardView: View {
    let countries: [(country: String, count: Int)]
    let totalCountries: Int

    @State private var animateBars = false

    private var top10: [(offset: Int, element: (country: String, count: Int))] {
        Array(countries.prefix(10).enumerated())
    }

    private var maxCount: Int {
        countries.first?.count ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // MARK: - Header
            HStack {
                Text("YOUR COUNTRIES")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(DesignTokens.textTertiary)

                Spacer()

                Text("\(totalCountries)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(DesignTokens.teal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DesignTokens.teal.opacity(0.15))
                    .clipShape(Capsule())
            }

            // MARK: - Country Rows
            ForEach(top10, id: \.offset) { index, item in
                countryRow(index: index, country: item.country, count: item.count)
            }
        }
        .padding(24)
        .glassCard()
        .onAppear {
            withAnimation {
                animateBars = true
            }
        }
    }

    // MARK: - Row

    private func countryRow(index: Int, country: String, count: Int) -> some View {
        HStack(spacing: 12) {
            // Medal / flag
            ZStack {
                if index < 3 {
                    Circle()
                        .fill(medalColor(index).opacity(0.2))
                        .frame(width: 32, height: 32)
                }

                Text(CountryFlags.flag(forCountry: country))
                    .font(.title3)
            }
            .frame(width: 32)

            // Country name
            Text(country)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)

            // Animated bar
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [DesignTokens.teal, DesignTokens.lavender.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: animateBars
                            ? geo.size.width * CGFloat(count) / CGFloat(maxCount)
                            : 0
                    )
            }
            .frame(height: 20)
            .animation(
                .spring(response: 0.6, dampingFraction: 0.8)
                    .delay(Double(index) * 0.08),
                value: animateBars
            )

            // Count pill
            Text("\(count)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 28, alignment: .trailing)
        }
        .frame(height: 32)
    }

    // MARK: - Medal Colors

    private func medalColor(_ index: Int) -> Color {
        switch index {
        case 0: return Color(red: 1.0, green: 0.84, blue: 0.0)    // Gold
        case 1: return Color(red: 0.75, green: 0.75, blue: 0.78)  // Silver
        case 2: return Color(red: 0.80, green: 0.50, blue: 0.20)  // Bronze
        default: return .clear
        }
    }
}
