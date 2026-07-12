import SwiftUI
import WidgetKit

struct NetworkWidget: Widget {
    let kind = "NetworkWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseBarTimelineProvider()) { entry in
            NetworkWidgetView(entry: entry)
        }
        .configurationDisplayName("Network")
        .description("Download and upload throughput.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct NetworkWidgetView: View {
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
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                Label("Network", systemImage: "arrow.up.arrow.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                rateLine(symbol: "arrow.down", value: snapshot.netDownBytesPerSecond, style: .title3, tint: .accentColor)
                rateLine(symbol: "arrow.up", value: snapshot.netUpBytesPerSecond, style: .callout, tint: .secondary)
                Spacer(minLength: 0)
            }
            .padding(4)

        case .systemMedium:
            HStack(spacing: 20) {
                column(title: "Download", symbol: "arrow.down", value: snapshot.netDownBytesPerSecond, tint: .accentColor)
                Divider()
                column(title: "Upload", symbol: "arrow.up", value: snapshot.netUpBytesPerSecond, tint: .secondary)
            }
            .padding(4)

        case .systemLarge:
            VStack(alignment: .leading, spacing: 16) {
                Label("Network", systemImage: "arrow.up.arrow.down")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 20) {
                    column(title: "Download", symbol: "arrow.down", value: snapshot.netDownBytesPerSecond, tint: .accentColor)
                    Divider()
                    column(title: "Upload", symbol: "arrow.up", value: snapshot.netUpBytesPerSecond, tint: .secondary)
                }
                Divider()
                HStack {
                    statLine("Processes", "\(snapshot.runningProcessCount)")
                    Spacer()
                    statLine("Dev servers", "\(snapshot.devServers.count)")
                }
            }
            .padding(4)

        default:
            EmptyView()
        }
    }

    private func rateLine(symbol: String, value: UInt64, style: Font, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2)
            Text(ByteFormatting.rate(value))
                .font(style.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .widgetAccentable()
    }

    private func column(title: String, symbol: String, value: UInt64, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(ByteFormatting.rate(value))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.callout.weight(.medium)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

#Preview("Network — Small", as: .systemSmall) {
    NetworkWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
    PulseBarEntry(date: .now, snapshot: nil)
}

#Preview("Network — Medium", as: .systemMedium) {
    NetworkWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
}

#Preview("Network — Large", as: .systemLarge) {
    NetworkWidget()
} timeline: {
    PulseBarEntry(date: .now, snapshot: .placeholder)
}
