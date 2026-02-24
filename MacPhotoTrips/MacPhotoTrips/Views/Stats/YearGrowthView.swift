import SwiftUI

/// Year-over-year growth chart with animated line graphs for trips and days abroad.
struct YearGrowthView: View {
    let tripsPerYear: [(year: Int, count: Int)]
    let daysPerYear: [(year: Int, days: Int)]
    let busiestYear: YearSummary?

    @State private var animateLine = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // MARK: - Header
            Text("YEAR OVER YEAR")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(DesignTokens.textTertiary)

            // MARK: - Trips Chart
            chartSection(
                title: "Trips",
                data: tripsPerYear.map { (label: "\($0.year)", value: $0.count) },
                color: DesignTokens.teal
            )

            // MARK: - Days Abroad Chart
            chartSection(
                title: "Days Abroad",
                data: daysPerYear.map { (label: "\($0.year)", value: $0.days) },
                color: DesignTokens.lavender
            )

            // MARK: - Auto-insight
            if let busiest = busiestYear {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.teal)

                    Text("\(busiest.year) was your biggest year — \(busiest.tripsCount) trips across \(busiest.countries.count) countries")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
        }
        .padding(24)
        .glassCard()
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).delay(0.2)) {
                animateLine = true
            }
        }
    }

    // MARK: - Chart Section

    private func chartSection(
        title: String,
        data: [(label: String, value: Int)],
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let maxVal = CGFloat(data.map(\.value).max() ?? 1)
                let stepX = data.count > 1 ? width / CGFloat(data.count - 1) : width

                ZStack {
                    // Grid lines
                    ForEach(0..<4, id: \.self) { i in
                        Path { path in
                            let y = height * CGFloat(i) / 3.0
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: width, y: y))
                        }
                        .stroke(Color.white.opacity(0.04))
                    }

                    // Gradient fill
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: height))
                        for (index, item) in data.enumerated() {
                            let x = data.count > 1 ? CGFloat(index) * stepX : width / 2
                            let y = height - (CGFloat(item.value) / maxVal * height * 0.85)
                            if index == 0 {
                                path.addLine(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        let lastX = data.count > 1 ? CGFloat(data.count - 1) * stepX : width / 2
                        path.addLine(to: CGPoint(x: lastX, y: height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [
                                color.opacity(animateLine ? 0.3 : 0),
                                color.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Line
                    Path { path in
                        for (index, item) in data.enumerated() {
                            let x = data.count > 1 ? CGFloat(index) * stepX : width / 2
                            let y = height - (CGFloat(item.value) / maxVal * height * 0.85)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .trim(from: 0, to: animateLine ? 1 : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    // Dots and value labels
                    ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                        let x = data.count > 1 ? CGFloat(index) * stepX : width / 2
                        let y = height - (CGFloat(item.value) / maxVal * height * 0.85)
                        let isLast = index == data.count - 1

                        // Value label
                        Text("\(item.value)")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(color)
                            .position(x: x, y: y - 14)
                            .opacity(animateLine ? 1 : 0)

                        // Dot
                        if isLast {
                            // Last point: larger dot with ring
                            Circle()
                                .fill(color)
                                .frame(width: 8, height: 8)
                                .overlay(
                                    Circle()
                                        .stroke(color.opacity(0.3), lineWidth: 1)
                                        .frame(width: 14, height: 14)
                                )
                                .position(x: x, y: y)
                                .opacity(animateLine ? 1 : 0)
                        } else {
                            Circle()
                                .fill(color)
                                .frame(width: 5, height: 5)
                                .position(x: x, y: y)
                                .opacity(animateLine ? 0.6 : 0)
                        }
                    }
                }
            }
            .frame(height: 100)

            // Year labels
            HStack {
                ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                    Text(String(item.label.suffix(2)))
                        .font(.system(size: 9))
                        .foregroundStyle(DesignTokens.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
