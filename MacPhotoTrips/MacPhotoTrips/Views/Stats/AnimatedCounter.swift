import SwiftUI

/// Animates an integer from 0 to `target` with a numeric text transition.
struct AnimatedCounter: View {
    let target: Int
    let font: Font
    let color: AnyShapeStyle
    var suffix: String = ""
    var prefix: String = ""
    var duration: Double = 0.8

    @State private var current: Double = 0
    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: 2) {
            if !prefix.isEmpty {
                Text(prefix)
                    .font(font)
                    .foregroundStyle(color)
            }

            Text("\(Int(current))")
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText(value: current))

            if !suffix.isEmpty {
                Text(suffix)
                    .font(font)
                    .foregroundStyle(color)
            }
        }
        .accessibilityLabel("\(target)\(suffix)")
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            withAnimation(.easeOut(duration: duration)) {
                current = Double(target)
            }
        }
    }
}

/// Animates a decimal number from 0 to `target` with configurable fraction digits.
struct AnimatedDecimalCounter: View {
    let target: Double
    let decimals: Int
    let font: Font
    let color: AnyShapeStyle
    var suffix: String = ""
    var duration: Double = 0.8

    @State private var current: Double = 0
    @State private var hasAppeared = false

    private static var formatterCache: [Int: NumberFormatter] = [:]

    private func formatNumber(_ value: Double) -> String {
        let nf: NumberFormatter
        if let cached = Self.formatterCache[decimals] {
            nf = cached
        } else {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.minimumFractionDigits = decimals
            f.maximumFractionDigits = decimals
            Self.formatterCache[decimals] = f
            nf = f
        }
        return nf.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(formatNumber(current))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText(value: current))

            if !suffix.isEmpty {
                Text(suffix)
                    .font(font)
                    .foregroundStyle(color)
            }
        }
        .accessibilityLabel(formatNumber(target) + suffix)
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            withAnimation(.easeOut(duration: duration)) {
                current = target
            }
        }
    }
}
