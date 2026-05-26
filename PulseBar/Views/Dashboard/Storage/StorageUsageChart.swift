import SwiftUI

/// Horizontal stacked-capsule chart for Used / Purgeable / Free.
struct StorageUsageChart: View {
    let usage: DiskUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let total = max(usage.totalBytes, 1)
                let usedWidth = geo.size.width * CGFloat(usage.usedBytes) / CGFloat(total)
                let purgeableWidth = geo.size.width * CGFloat(usage.purgeableBytes) / CGFloat(total)
                let freeWidth = max(0, geo.size.width - usedWidth - purgeableWidth)

                HStack(spacing: 0) {
                    Rectangle().fill(Color.accentColor)
                        .frame(width: usedWidth)
                    Rectangle().fill(Color.secondary.opacity(0.35))
                        .frame(width: purgeableWidth)
                    Rectangle().fill(Color.secondary.opacity(0.15))
                        .frame(width: freeWidth)
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)

            HStack(spacing: 18) {
                legendSwatch(color: .accentColor, label: "Used", value: usage.usedFormatted)
                if usage.purgeableBytes > 0 {
                    legendSwatch(color: .secondary.opacity(0.5), label: "Purgeable", value: usage.purgeableFormatted)
                }
                legendSwatch(color: .secondary.opacity(0.3), label: "Free", value: usage.freeFormatted)
                Spacer()
            }
            .font(.caption)
        }
    }

    private func legendSwatch(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().fontWeight(.medium)
        }
    }
}
