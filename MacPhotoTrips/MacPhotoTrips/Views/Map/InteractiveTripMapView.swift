import SwiftUI
import MapKit

/// Satellite map with tappable annotation dots.
struct InteractiveTripMapView: View {
    let annotations: [DashboardViewModel.StopAnnotation]
    let onAnnotationTap: (DashboardViewModel.StopAnnotation) -> Void

    var body: some View {
        Map {
            ForEach(annotations) { stop in
                Annotation(stop.city, coordinate: stop.coordinate) {
                    Circle()
                        .fill(DesignTokens.teal)
                        .frame(
                            width: annotationSize(for: stop.days),
                            height: annotationSize(for: stop.days)
                        )
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: DesignTokens.teal.opacity(0.4), radius: 4)
                        // 44pt minimum hit area for accessibility
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Circle().size(width: 44, height: 44))
                        .onTapGesture {
                            onAnnotationTap(stop)
                        }
                }
            }
        }
        .mapStyle(.imagery)
    }

    private func annotationSize(for days: Int) -> CGFloat {
        let base: CGFloat = 8
        let scale = min(CGFloat(days), 14) / 14
        return base + scale * 16
    }
}
