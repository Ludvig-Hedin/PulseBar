import SwiftUI

/// Metric card with optional progress bar + sparkline. Colour is driven by severity
/// so the user can spot trouble without reading digits.
struct MetricCard: View {
    let title: String
    let icon: String
    let value: String
    let subtitle: String
    /// 0..1 — renders a progress bar below the value. Pass nil to skip.
    var progress: Double? = nil
    var tint: Color = .accentColor
    /// Small time-series shown as a sparkline. Values in 0..100.
    var history: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer()
                if !history.isEmpty {
                    Sparkline(values: history)
                        .stroke(tint, lineWidth: 1.5)
                        .frame(width: 64, height: 22)
                }
            }
            Text(value)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(tint)
            if let p = progress {
                ProgressView(value: max(0, min(1, p)))
                    .tint(tint)
            }
            Text(subtitle)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Lightweight Shape-based sparkline. No third-party charting dependency.
private struct Sparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let maxV = max(values.max() ?? 1, 1)
        let minV = values.min() ?? 0
        let range = max(maxV - minV, 1)
        let stepX = rect.width / CGFloat(values.count - 1)
        for (i, v) in values.enumerated() {
            let x = CGFloat(i) * stepX
            let y = rect.height - ((CGFloat(v - minV) / CGFloat(range)) * rect.height)
            if i == 0 { path.move(to: .init(x: x, y: y)) }
            else { path.addLine(to: .init(x: x, y: y)) }
        }
        return path
    }
}
