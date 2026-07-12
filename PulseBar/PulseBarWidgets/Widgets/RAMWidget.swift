import SwiftUI
import WidgetKit

struct RAMWidget: Widget {
    let kind = "RAMWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseBarTimelineProvider()) { entry in
            RAMWidgetView(entry: entry)
        }
        .configurationDisplayName("Memory")
        .description("RAM used and available.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct RAMWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PulseBarEntry

    var body: some View {
        let snapshot = entry.snapshot ?? .placeholder
        let tint = WidgetPalette.tint(snapshot.ramUsedPercent, warn: 70, critical: 85)

        content(snapshot: snapshot, tint: tint)
            .staleDimmed(entry.isStale)
            .overlay(alignment: .bottomTrailing) {
                if entry.isStale { WidgetEmptyState() }
            }
            .containerBackground(.background, for: .widget)
    }

    @ViewBuilder
    private func content(snapshot: WidgetSnapshot, tint: Color) -> some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                Label("Memory", systemImage: "memorychip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ByteFormatting.gigabytes(snapshot.ramUsedBytes))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .widgetAccentable()
                Text("\(Int(snapshot.ramUsedPercent.rounded()))% used")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ProgressView(value: snapshot.ramUsedRatio)
                    .tint(tint)
            }
            .padding(4)

        case .systemMedium:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Memory", systemImage: "memorychip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if snapshot.ramHistory.count > 1 {
                        MiniSparkline(values: snapshot.ramHistory)
                            .stroke(tint, lineWidth: 1.5)
                            .frame(width: 64, height: 22)
                    }
                }
                Text(ByteFormatting.gigabytes(snapshot.ramUsedBytes))
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .widgetAccentable()
                ProgressView(value: snapshot.ramUsedRatio)
                    .tint(tint)
                Text("of \(ByteFormatting.gigabytes(snapshot.ramTotalBytes)) · \(Int(snapshot.ramUsedPercent.rounded()))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(4)

        case .systemLarge:
            VStack(alignment: .leading, spacing: 12) {
                Label("Memory", systemImage: "memorychip")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(ByteFormatting.gigabytes(snapshot.ramUsedBytes))
                    .font(.system(.largeTitle, design: .default).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .widgetAccentable()
                ProgressView(value: snapshot.ramUsedRatio)
                    .tint(tint)
                if snapshot.ramHistory.count > 1 {
                    MiniSparkline(values: snapshot.ramHistory)
                        .stroke(tint, lineWidth: 2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                Text("\(ByteFormatting.gigabytes(snapshot.ramUsedBytes)) of \(ByteFormatting.gigabytes(snapshot.ramTotalBytes)) · \(pressureLabel(snapshot.ramPressure))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)

        default:
            EmptyView()
        }
    }

    private func pressureLabel(_ raw: String) -> String {
        switch raw {
        case "critical": return "Critical pressure"
        case "warning": return "Elevated pressure"
        default: return "Normal pressure"
        }
    }
}

#Preview("RAM — Small", as: .systemSmall) {
    RAMWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
    PulseBarEntry(date: .now, snapshot: nil)
}

#Preview("RAM — Medium", as: .systemMedium) {
    RAMWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
}

#Preview("RAM — Large", as: .systemLarge) {
    RAMWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
}
