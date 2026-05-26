import SwiftUI

/// Circular usage gauge with color-coded stress tint.
/// Plain `Shape` — no external charting dependency.
struct StorageGauge: View {
    let usedRatio: Double
    let centerLabel: String
    let centerSublabel: String
    var lineWidth: CGFloat = 16
    var size: CGFloat = 200

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, usedRatio))))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: gradientColors),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: usedRatio)

            VStack(spacing: 4) {
                Text(centerLabel)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(stressTint)
                    .monospacedDigit()
                Text(centerSublabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private var stressTint: Color {
        if usedRatio >= 0.85 { return .red }
        if usedRatio >= 0.70 { return .orange }
        return .green
    }

    private var gradientColors: [Color] {
        if usedRatio >= 0.85 { return [.orange, .red] }
        if usedRatio >= 0.70 { return [.yellow, .orange] }
        return [.accentColor.opacity(0.7), .accentColor]
    }
}
