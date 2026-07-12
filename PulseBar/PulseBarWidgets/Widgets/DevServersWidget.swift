import SwiftUI
import WidgetKit

struct DevServersWidget: Widget {
    let kind = "DevServersWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseBarTimelineProvider()) { entry in
            DevServersWidgetView(entry: entry)
        }
        .configurationDisplayName("Dev Servers")
        .description("Running local dev servers.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct DevServersWidgetView: View {
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
        let servers = Array(snapshot.devServers.prefix(rowCount))

        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                Label("Dev Servers", systemImage: "terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let first = servers.first {
                    Text(first.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(":\(first.port)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                        .widgetAccentable()
                    if snapshot.devServers.count > 1 {
                        Text("+\(snapshot.devServers.count - 1) more")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Spacer(minLength: 0)
                    Text("No dev servers running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(4)

        case .systemMedium, .systemLarge:
            VStack(alignment: .leading, spacing: 10) {
                Label("Dev Servers", systemImage: "terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if servers.isEmpty {
                    Spacer(minLength: 0)
                    Text("No dev servers running")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else {
                    ForEach(servers) { server in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(server.name)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                if let kind = server.kind {
                                    Text(kind)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(":\(server.port)")
                                .font(.callout.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.accentColor)
                                .widgetAccentable()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(4)

        default:
            EmptyView()
        }
    }
}

#Preview("Dev Servers — Small", as: .systemSmall) {
    DevServersWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
    PulseBarEntry(date: .now, snapshot: nil)
}

#Preview("Dev Servers — Medium", as: .systemMedium) {
    DevServersWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
}

#Preview("Dev Servers — Large", as: .systemLarge) {
    DevServersWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
}
