import SwiftUI

/// Aurora Glass design tokens — port of CSS custom properties from dashboard.html.
enum DesignTokens {
    // MARK: - Colors
    static let bg = Color(red: 8/255, green: 10/255, blue: 20/255)       // #080a14
    static let teal = Color(red: 77/255, green: 217/255, blue: 192/255)  // #4dd9c0
    static let lavender = Color(red: 167/255, green: 139/255, blue: 250/255) // #a78bfa
    static let rose = Color(red: 244/255, green: 114/255, blue: 182/255) // #f472b6

    static let gradient = LinearGradient(
        colors: [teal, lavender, rose],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glassBorder = Color.white.opacity(0.08)
    static let glassBorderHover = Color.white.opacity(0.14)
    static let textSecondary = Color.white.opacity(0.50)
    static let textTertiary = Color.white.opacity(0.25)
}

/// Glass card modifier — port of the .glass CSS class.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial.opacity(0.5))
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(DesignTokens.glassBorder, lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}
