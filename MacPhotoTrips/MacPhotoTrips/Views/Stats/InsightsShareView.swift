import SwiftUI

/// Share button that renders a branded travel-stats card and opens the system share sheet.
struct InsightsShareButton: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showShare = false
    @State private var shareImage: UIImage?

    var body: some View {
        Button(action: renderAndShare) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("Share Your Travel Story")
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [DesignTokens.teal, DesignTokens.lavender],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .sheet(isPresented: $showShare) {
            if let image = shareImage {
                ShareSheet(items: [image])
            }
        }
    }

    private func renderAndShare() {
        let card = InsightsShareCard(viewModel: viewModel)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0
        if let image = renderer.uiImage {
            shareImage = image
            showShare = true
        }
    }
}

// MARK: - Branded Share Card (rendered off-screen via ImageRenderer)

/// 360x640pt card (at 3x = 1080x1920 — Instagram story size).
/// Never displayed in the UI directly; only used by ImageRenderer.
private struct InsightsShareCard: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // MARK: Hero — country count
            heroSection

            // MARK: Key stats row
            keyStatsRow

            // MARK: Top records
            topRecords

            Spacer()

            // MARK: Branding footer
            brandingFooter
        }
        .frame(width: 360, height: 640)
        .background(cardBackground)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 4) {
            Text("I've explored")
                .font(.title2.weight(.light))
                .foregroundStyle(.white.opacity(0.8))

            Text("\(viewModel.countriesCount)")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [DesignTokens.teal, DesignTokens.lavender],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("countries")
                .font(.title.weight(.light))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: - Key Stats Row

    private var keyStatsRow: some View {
        HStack {
            statCell(value: viewModel.totalTrips, label: "TRIPS")
            Spacer()
            statCell(value: viewModel.totalDays, label: "DAYS")
            Spacer()
            statCell(value: viewModel.totalCities, label: "CITIES")
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }

    private func statCell(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Top Records

    private var topRecords: some View {
        VStack(spacing: 12) {
            if let farthest = viewModel.farthestTrip {
                recordRow(
                    icon: "arrow.up.right.circle",
                    text: "Farthest: \(formatNumber(Int(farthest.distanceKm))) km to \(farthest.city)"
                )
            }

            if let longest = viewModel.longestTrip {
                recordRow(
                    icon: "calendar.badge.clock",
                    text: "Longest: \(longest.durationDays) days — \(viewModel.tripLabel(longest))"
                )
            }

            if let photogenic = viewModel.mostPhotogenicTrip {
                recordRow(
                    icon: "camera.fill",
                    text: "\(formatNumber(photogenic.photoCount)) photos — \(viewModel.tripLabel(photogenic))"
                )
            }
        }
        .padding(.horizontal, 24)
    }

    private func recordRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(DesignTokens.teal)
                .frame(width: 20)

            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)

            Spacer()
        }
    }

    // MARK: - Branding Footer

    private var brandingFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe.europe.africa")
                .font(.caption)
                .foregroundStyle(DesignTokens.teal)

            Text("MacPhoto Trips")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.bottom, 24)
    }

    // MARK: - Background

    private var cardBackground: some View {
        ZStack {
            DesignTokens.bg

            // Teal blob
            Circle()
                .fill(DesignTokens.teal)
                .frame(width: 300, height: 200)
                .opacity(0.15)
                .blur(radius: 80)
                .offset(x: -60, y: -150)

            // Lavender blob
            Circle()
                .fill(DesignTokens.lavender)
                .frame(width: 250, height: 250)
                .opacity(0.12)
                .blur(radius: 80)
                .offset(x: 80, y: 200)
        }
    }

    // MARK: - Helpers

    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
