import SwiftUI

/// Flat-stroke usage ring for widget canvases. Adapted from the dashboard's
/// `StorageGauge` but with no `AngularGradient` and no continuous spring
/// animation — widgets are system-redrawn snapshots, not live views.
struct RingGauge: View {
    let usedRatio: Double
    let tint: Color
    var lineWidth: CGFloat = 8
    var size: CGFloat = 60

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, usedRatio))))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .frame(width: size, height: size)
    }
}
