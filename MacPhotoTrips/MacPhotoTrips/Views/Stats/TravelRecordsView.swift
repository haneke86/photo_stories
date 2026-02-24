import SwiftUI

/// Achievement-style travel record cards — farthest trip, longest streak, etc.
struct TravelRecordsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var visibleCards: Set<Int> = []
    @State private var records: [TravelRecord] = []

    var body: some View {
        VStack(spacing: 12) {
            // Section header
            Text("RECORDS & STREAKS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(DesignTokens.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Record cards
            ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                recordCard(record: record, color: record.accentColor)
                    .opacity(visibleCards.contains(index) ? 1 : 0)
                    .offset(y: visibleCards.contains(index) ? 0 : 16)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.8)
                            .delay(Double(index) * 0.1),
                        value: visibleCards.contains(index)
                    )
                    .onAppear {
                        visibleCards.insert(index)
                    }
            }
        }
        .onAppear {
            if records.isEmpty {
                records = buildRecords()
            }
        }
    }

    // MARK: - Record Card

    private func recordCard(record: TravelRecord, color: Color) -> some View {
        HStack(spacing: 16) {
            // Icon badge
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: record.icon)
                    .foregroundStyle(color)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(record.label.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(DesignTokens.textTertiary)

                Text(record.value)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)

                Text(record.detail)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(16)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3)
        }
        .glassCard()
    }

    // MARK: - Build Records

    private struct TravelRecord {
        let icon: String
        let label: String
        let value: String
        let detail: String
        let accentColor: Color
    }

    private static let accentColors: [Color] = [
        DesignTokens.teal,
        DesignTokens.lavender,
        DesignTokens.rose
    ]

    private func buildRecords() -> [TravelRecord] {
        var records: [TravelRecord] = []

        // 1. Farthest from Home
        if let farthest = viewModel.farthestTrip {
            let formatted = Self.formatNumber(Int(farthest.distanceKm))
            records.append(TravelRecord(
                icon: "arrow.up.right.circle",
                label: "Farthest from Home",
                value: "\(formatted) km",
                detail: "\(farthest.city) — \(viewModel.tripLabel(farthest.trip))",
                accentColor: Self.accentColors[records.count % 3]
            ))
        }

        // 2. Longest Trip
        if let longest = viewModel.longestTrip {
            records.append(TravelRecord(
                icon: "calendar.badge.clock",
                label: "Longest Trip",
                value: "\(longest.durationDays) days",
                detail: viewModel.tripLabel(longest),
                accentColor: Self.accentColors[records.count % 3]
            ))
        }

        // 3. Most Cities in One Trip
        if let mostCities = viewModel.mostCitiesTrip {
            records.append(TravelRecord(
                icon: "point.3.connected.trianglepath.dotted",
                label: "Most Cities in One Trip",
                value: "\(mostCities.cityCount) cities",
                detail: viewModel.tripLabel(mostCities.trip),
                accentColor: Self.accentColors[records.count % 3]
            ))
        }

        // 4. Longest Home Stretch
        if let homeStretch = viewModel.longestHomeStretch {
            records.append(TravelRecord(
                icon: "house.fill",
                label: "Longest Home Stretch",
                value: "\(homeStretch.days) days",
                detail: "Between \(homeStretch.fromTrip) and \(homeStretch.toTrip)",
                accentColor: Self.accentColors[records.count % 3]
            ))
        }

        // 5. Busiest Month
        if let busiest = viewModel.busiestMonth {
            records.append(TravelRecord(
                icon: "flame.fill",
                label: "Busiest Month",
                value: "\(busiest.month) \(busiest.year)",
                detail: "\(busiest.tripCount) trips departing",
                accentColor: Self.accentColors[records.count % 3]
            ))
        }

        // 6. Most Photos
        if let photogenic = viewModel.mostPhotogenicTrip {
            let formatted = Self.formatNumber(photogenic.photoCount)
            records.append(TravelRecord(
                icon: "camera.fill",
                label: "Most Photos",
                value: "\(formatted) photos",
                detail: viewModel.tripLabel(photogenic),
                accentColor: Self.accentColors[records.count % 3]
            ))
        }

        return records
    }

    // MARK: - Helpers

    private static let numberFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        return nf
    }()

    /// Format an integer with comma grouping (e.g. 12345 -> "12,345").
    private static func formatNumber(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
