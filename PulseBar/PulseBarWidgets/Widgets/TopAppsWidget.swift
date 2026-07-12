import SwiftUI
import WidgetKit

struct TopAppsWidget: Widget {
    let kind = "TopAppsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseBarTimelineProvider()) { entry in
            TopAppsWidgetView(entry: entry)
        }
        .configurationDisplayName("Top Apps")
        .description("Processes using the most CPU right now.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct TopAppsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PulseBarEntry

    var body: some View {
        let snapshot = entry.snapshot ?? .placeholder

        content(snapshot: snapshot)
            .staleDimmed(entry.isStale)
            .overlay(alignment: .bottomTrailing) {
                if entry.isStale { WidgetEmptyState() }
            }
            .containerBackground(.background, for: .widget)
    }

    @ViewBuilder
    private func content(snapshot: WidgetSnapshot) -> some View {
        let rowCount = family == .systemLarge ? 5 : (family == .systemMedium ? 3 : 1)
        let rows = Array(snapshot.topProcesses.prefix(rowCount))

        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                Label("Top Apps", systemImage: "list.bullet.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let top = rows.first {
                    HStack(spacing: 6) {
                        Image(systemName: symbol(for: top.kind))
                            .foregroundStyle(.secondary)
                        Text(top.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                    }
                    Text("\(Int(top.cpuPercent.rounded()))% CPU")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                        .widgetAccentable()
                } else {
                    Text("No data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(4)

        case .systemMedium, .systemLarge:
            VStack(alignment: .leading, spacing: 10) {
                Label("Top Apps", systemImage: "list.bullet.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(rows) { proc in
                    HStack(spacing: 8) {
                        Image(systemName: symbol(for: proc.kind))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(proc.name)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        if family == .systemLarge {
                            Text(ByteFormatting.memory(proc.memoryBytes))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Text("\(Int(proc.cpuPercent.rounded()))%")
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.accentColor)
                            .widgetAccentable()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(4)

        default:
            EmptyView()
        }
    }

    private func symbol(for kind: String) -> String {
        switch kind {
        case ProcessRowKind.app.rawValue: return "app.fill"
        case ProcessRowKind.cli.rawValue: return "terminal"
        default: return "gearshape.fill"
        }
    }
}

/// Mirrors `ProcessRow.Kind`'s raw values without importing the main app's
/// process-sampling code into the sandboxed widget target.
private enum ProcessRowKind: String {
    case app = "App"
    case cli = "CLI"
    case background = "Background"
    case unknown = "Unknown"
}

#Preview("Top Apps — Small", as: .systemSmall) {
    TopAppsWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
    PulseBarEntry(date: .now, snapshot: nil)
}

#Preview("Top Apps — Medium", as: .systemMedium) {
    TopAppsWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
}

#Preview("Top Apps — Large", as: .systemLarge) {
    TopAppsWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
}
