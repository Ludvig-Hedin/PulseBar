import SwiftUI

/// Same line-path math as the dashboard's `MetricCard` sparkline, promoted
/// here so both the widget extension and the main app can each build one
/// without a cross-target dependency.
struct MiniSparkline: Shape {
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
