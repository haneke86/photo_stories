import SwiftUI

/// Trips | Countries | Days stat strip — port of CSS .stats-strip.
struct StatsStripView: View {
    let viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: 2) {
            StatCell(value: "\(viewModel.totalTrips)", label: "TRIPS")
            StatCell(value: "\(viewModel.countriesCount)", label: "COUNTRIES")
            StatCell(value: "\(viewModel.totalDays)", label: "DAYS")
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(DesignTokens.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial.opacity(0.5))
        .background(Color.white.opacity(0.04))
    }
}
