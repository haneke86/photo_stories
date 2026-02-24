import SwiftUI
import MapKit

/// MapKit map with stop annotations, sized by duration.
/// Uses .imagery style (satellite) instead of Plotly.
struct TripMapView: View {
    let annotations: [DashboardViewModel.StopAnnotation]
    var isFullScreen: Bool = false

    var body: some View {
        Map {
            ForEach(annotations) { stop in
                Annotation(stop.city, coordinate: stop.coordinate) {
                    Circle()
                        .fill(DesignTokens.teal)
                        .frame(width: annotationSize(for: stop.days),
                               height: annotationSize(for: stop.days))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: DesignTokens.teal.opacity(0.4), radius: 4)
                }
            }
        }
        .mapStyle(.imagery)
        .frame(height: isFullScreen ? nil : 260)
        .if(!isFullScreen) { view in
            view
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(DesignTokens.glassBorder, lineWidth: 1)
                )
        }
        .allowsHitTesting(isFullScreen)
    }

    /// Scale annotation size by stop duration (min 8pt, max 24pt).
    private func annotationSize(for days: Int) -> CGFloat {
        let base: CGFloat = 8
        let scale = min(CGFloat(days), 14) / 14  // cap at 14 days
        return base + scale * 16
    }
}

// MARK: - Conditional Modifier

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
