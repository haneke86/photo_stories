import SwiftUI

/// "21 countries since 2020" header — port of CSS .hero section.
struct HeroView: View {
    let viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR TRAVEL STORY")
                .font(.caption2)
                .fontWeight(.medium)
                .tracking(3)
                .foregroundStyle(DesignTokens.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(viewModel.countriesCount)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.gradient)

                Text("countries\nsince \(viewModel.sinceYear)")
                    .font(.title)
                    .fontWeight(.light)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(2)
            }

            Text("\(viewModel.totalTrips) trips from \(viewModel.homeCity)")
                .font(.subheadline)
                .fontWeight(.light)
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 48)
    }
}
