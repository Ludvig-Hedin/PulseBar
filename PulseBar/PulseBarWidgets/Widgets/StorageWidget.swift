import SwiftUI
import WidgetKit

struct StorageWidget: Widget {
    let kind = "StorageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseBarTimelineProvider()) { entry in
            StorageWidgetView(entry: entry)
        }
        .configurationDisplayName("Storage")
        .description("Disk space used and free.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct StorageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PulseBarEntry

    var body: some View {
        let snapshot = entry.snapshot ?? .placeholder
        let hasDisk = snapshot.diskTotalBytes != nil
        let tint = WidgetPalette.tint(snapshot.diskUsedPercent, warn: 70, critical: 85)

        Group {
            if hasDisk {
                content(snapshot: snapshot, tint: tint)
            } else {
                WidgetEmptyState()
            }
        }
        .staleDimmed(entry.isStale)
        .overlay(alignment: .bottomTrailing) {
            if entry.isStale && hasDisk { WidgetEmptyState() }
        }
        .containerBackground(.background, for: .widget)
    }

    @ViewBuilder
    private func content(snapshot: WidgetSnapshot, tint: Color) -> some View {
        switch family {
        case .systemSmall:
            VStack(spacing: 8) {
                RingGauge(usedRatio: snapshot.diskUsedRatio, tint: tint, lineWidth: 8, size: 56)
                    .overlay {
                        Text("\(Int(snapshot.diskUsedPercent.rounded()))%")
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                    }
                Text(freeOfTotal(snapshot))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(4)

        case .systemMedium:
            HStack(spacing: 16) {
                RingGauge(usedRatio: snapshot.diskUsedRatio, tint: tint, lineWidth: 8, size: 64)
                    .overlay {
                        Text("\(Int(snapshot.diskUsedPercent.rounded()))%")
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Label("Storage", systemImage: "internaldrive.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(freeText(snapshot))
                        .font(.callout.weight(.medium))
                    Text(totalText(snapshot))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(4)

        case .systemLarge:
            VStack(alignment: .leading, spacing: 16) {
                Label("Storage", systemImage: "internaldrive.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 20) {
                    RingGauge(usedRatio: snapshot.diskUsedRatio, tint: tint, lineWidth: 10, size: 90)
                        .overlay {
                            Text("\(Int(snapshot.diskUsedPercent.rounded()))%")
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(tint)
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(freeText(snapshot))
                            .font(.title3.weight(.medium))
                        Text(totalText(snapshot))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: snapshot.diskUsedRatio)
                    .tint(tint)
            }
            .padding(4)

        default:
            EmptyView()
        }
    }

    private func freeOfTotal(_ s: WidgetSnapshot) -> String {
        guard let free = s.diskFreeBytes, let total = s.diskTotalBytes else { return "" }
        return "\(ByteFormatting.gigabytes(free)) free of \(ByteFormatting.gigabytes(total))"
    }

    private func freeText(_ s: WidgetSnapshot) -> String {
        guard let free = s.diskFreeBytes else { return "" }
        return "\(ByteFormatting.gigabytes(free)) free"
    }

    private func totalText(_ s: WidgetSnapshot) -> String {
        guard let used = s.diskUsedBytes, let total = s.diskTotalBytes else { return "" }
        return "\(ByteFormatting.gigabytes(used)) used of \(ByteFormatting.gigabytes(total))"
    }
}

#Preview("Storage — Small", as: .systemSmall) {
    StorageWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
    PulseBarEntry(date: .now, snapshot: nil)
}

#Preview("Storage — Medium", as: .systemMedium) {
    StorageWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
}

#Preview("Storage — Large", as: .systemLarge) {
    StorageWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
}
