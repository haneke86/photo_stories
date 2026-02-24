import SwiftUI

/// Apple Fitness-inspired concentric rings showing trips, days, and cities.
struct StatRingsView: View {
    let trips: Int
    let days: Int
    let cities: Int
    let photos: Int
    let avgDays: Double

    @State private var animateRings = false

    private let ringWidth: CGFloat = 18
    private let ringGap: CGFloat = 6

    var body: some View {
        VStack(spacing: 24) {
            // MARK: - Concentric Rings
            ZStack {
                // Outer ring — trips (teal)
                ringView(
                    value: trips,
                    max: roundedMax(trips),
                    color: DesignTokens.teal,
                    size: 200
                )

                // Middle ring — days (lavender)
                ringView(
                    value: days,
                    max: roundedMax(days),
                    color: DesignTokens.lavender,
                    size: 200 - (ringWidth + ringGap) * 2
                )

                // Inner ring — cities (rose)
                ringView(
                    value: cities,
                    max: roundedMax(cities),
                    color: DesignTokens.rose,
                    size: 200 - (ringWidth + ringGap) * 4
                )
            }
            .frame(width: 200, height: 200)

            // MARK: - Ring Labels
            HStack(spacing: 24) {
                ringLabel(color: DesignTokens.teal, value: trips, label: "TRIPS")
                ringLabel(color: DesignTokens.lavender, value: days, label: "DAYS")
                ringLabel(color: DesignTokens.rose, value: cities, label: "CITIES")
            }

            // MARK: - Mini Stats Row
            miniStatsRow
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                animateRings = true
            }
        }
    }

    // MARK: - Ring View

    private func ringView(value: Int, max: Int, color: Color, size: CGFloat) -> some View {
        let progress = max > 0 ? CGFloat(value) / CGFloat(max) : 0

        return ZStack {
            // Background track
            Circle()
                .stroke(color.opacity(0.15), lineWidth: ringWidth)

            // Filled arc
            Circle()
                .trim(from: 0, to: animateRings ? progress : 0)
                .stroke(color, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.4), radius: 4)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Ring Label

    private func ringLabel(color: Color, value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(formatNumber(value))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(DesignTokens.textTertiary)
        }
    }

    // MARK: - Mini Stats Row

    private var miniStatsRow: some View {
        HStack(spacing: 2) {
            miniStatCell(value: formatNumber(photos), label: "PHOTOS")
            miniStatCell(value: String(format: "%.1f", avgDays), label: "AVG DAYS")
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func miniStatCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(DesignTokens.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial.opacity(0.5))
        .background(Color.white.opacity(0.04))
    }

    // MARK: - Helpers

    /// Returns the next "round" max for ring proportion scaling.
    func roundedMax(_ value: Int) -> Int {
        if value <= 10 { return 10 }
        if value <= 25 { return 25 }
        if value <= 50 { return 50 }
        if value <= 100 { return 100 }
        return ((value / 50) + 1) * 50
    }

    /// Formats an integer with locale-aware decimal grouping (e.g. 1,234).
    func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
