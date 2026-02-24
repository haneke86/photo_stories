import SwiftUI

/// Vertical mini-timeline with glowing dots — port of CSS .stops-list.
struct StopListView: View {
    let stops: [Stop]
    let tripCountry: String

    /// Cycle through accent colors for dots.
    private func dotColor(at index: Int) -> Color {
        let colors = [DesignTokens.teal, DesignTokens.lavender, DesignTokens.rose]
        return colors[index % colors.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                HStack(alignment: .top, spacing: 12) {
                    // Vertical line + dot
                    VStack(spacing: 0) {
                        if index > 0 {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [dotColor(at: index - 1), dotColor(at: index)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 1, height: 12)
                                .opacity(0.3)
                        } else {
                            Spacer().frame(height: 4)
                        }

                        // Glowing dot
                        Circle()
                            .fill(dotColor(at: index))
                            .frame(width: 7, height: 7)
                            .shadow(color: dotColor(at: index).opacity(0.5), radius: 3)

                        if index < stops.count - 1 {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [dotColor(at: index), dotColor(at: index + 1)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 1)
                                .opacity(0.3)
                        }
                    }
                    .frame(width: 7)

                    // Stop info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(stopLabel(stop))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)

                            Spacer()

                            Text("\(stop.days)d")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textTertiary)
                        }

                        if !stop.districts.isEmpty {
                            Text(stop.districts.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.textTertiary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.leading, 4)
    }

    private func stopLabel(_ stop: Stop) -> String {
        if stop.country != tripCountry {
            return "\(stop.city), \(stop.country)"
        }
        return stop.city
    }
}
