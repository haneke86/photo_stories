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

    private var formatter: NumberFormatter {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = decimals
        nf.maximumFractionDigits = decimals
        return nf
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(formatter.string(from: NSNumber(value: current)) ?? "0")
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
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            withAnimation(.easeOut(duration: duration)) {
                current = target
            }
        }
    }
}
