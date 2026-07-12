import SwiftUI
import WidgetKit

struct CPUWidget: Widget {
    let kind = "CPUWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseBarTimelineProvider()) { entry in
            CPUWidgetView(entry: entry)
        }
        .configurationDisplayName("CPU")
        .description("System processor load.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct CPUWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PulseBarEntry

    var body: some View {
        let snapshot = entry.snapshot ?? .placeholder
        let tint = WidgetPalette.tint(snapshot.cpuPercent, warn: 60, critical: 85)

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
                Label("CPU", systemImage: "cpu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(percentString(snapshot.cpuPercent))
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .widgetAccentable()
                Spacer(minLength: 0)
                if snapshot.cpuHistory.count > 1 {
                    MiniSparkline(values: snapshot.cpuHistory)
                        .stroke(tint, lineWidth: 1.5)
                        .frame(height: 20)
                }
            }
            .padding(4)

        case .systemMedium:
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("CPU", systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(percentString(snapshot.cpuPercent))
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .widgetAccentable()
                    Text("System load")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if snapshot.cpuHistory.count > 1 {
                    MiniSparkline(values: snapshot.cpuHistory)
                        .stroke(tint, lineWidth: 2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
            }
            .padding(4)

        case .systemLarge:
            VStack(alignment: .leading, spacing: 12) {
                Label("CPU", systemImage: "cpu")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(percentString(snapshot.cpuPercent))
                    .font(.system(.largeTitle, design: .default).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .widgetAccentable()
                if snapshot.cpuHistory.count > 1 {
                    MiniSparkline(values: snapshot.cpuHistory)
                        .stroke(tint, lineWidth: 2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                }
                HStack {
                    statLine("Peak", percentString(snapshot.cpuHistory.max() ?? snapshot.cpuPercent))
                    Spacer()
                    statLine("Avg", percentString(average(snapshot.cpuHistory)))
                    Spacer()
                    statLine("Processes", "\(snapshot.runningProcessCount)")
                }
            }
            .padding(4)

        default:
            EmptyView()
        }
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.callout.weight(.medium)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func percentString(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

#Preview("CPU — Small", as: .systemSmall) {
    CPUWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
    PulseBarEntry(date: .now, snapshot: nil)
}

#Preview("CPU — Medium", as: .systemMedium) {
    CPUWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
}

#Preview("CPU — Large", as: .systemLarge) {
    CPUWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
}
