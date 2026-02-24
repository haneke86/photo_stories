import SwiftUI

/// Compact trip list row — flag | city + date | duration pill | chevron.
struct TripRowView: View {
    let trip: Trip
    let viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Flag
            Text(viewModel.tripFlag(trip))
                .font(.title2)
                .frame(width: 32)

            // City label + date range
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.tripLabel(trip))
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(viewModel.tripDateRange(trip))
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }

            Spacer()

            // Duration pill
            Text("\(trip.durationDays)d")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DesignTokens.teal.opacity(0.12))
                .foregroundStyle(DesignTokens.teal)
                .clipShape(Capsule())

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(DesignTokens.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 14)
    }
}
