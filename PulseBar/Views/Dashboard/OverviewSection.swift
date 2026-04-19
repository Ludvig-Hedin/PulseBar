import SwiftUI

struct OverviewSection: View {
    @EnvironmentObject private var vm: PulseBarViewModel
    let snapshot: SystemSnapshot

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
            MetricCard(
                title: "CPU",
                icon: "cpu",
                value: NumberFormatting.percent(snapshot.cpuUsagePercent),
                subtitle: "System load",
                progress: snapshot.cpuUsagePercent / 100,
                tint: tint(for: snapshot.cpuUsagePercent, warn: 60, critical: 85),
                history: vm.cpuHistory
            )
            MetricCard(
                title: "Memory",
                icon: "memorychip",
                value: ByteFormatting.gigabytes(snapshot.memoryUsedBytes),
                subtitle: "of \(ByteFormatting.gigabytes(snapshot.memoryTotalBytes)) · \(Int(snapshot.memoryUsedPercent))%",
                progress: snapshot.memoryUsedRatio,
                tint: tint(for: snapshot.memoryUsedPercent, warn: 70, critical: 85),
                history: vm.ramHistory
            )
            MetricCard(
                title: "Network",
                icon: "arrow.up.arrow.down",
                value: "↓ \(ByteFormatting.rate(snapshot.networkDownloadBytesPerSecond))",
                subtitle: "↑ \(ByteFormatting.rate(snapshot.networkUploadBytesPerSecond))",
                progress: nil,
                tint: .accentColor,
                history: []
            )
            MetricCard(
                title: "Battery",
                icon: snapshot.batteryIsCharging ? "battery.100.bolt" : "battery.75",
                value: snapshot.batteryPercent.map { NumberFormatting.percent($0) } ?? "—",
                subtitle: snapshot.batteryMinutesRemaining.map { "\($0) min left" }
                    ?? (snapshot.batteryIsCharging ? "Charging" : "On battery"),
                progress: (snapshot.batteryPercent ?? 0) / 100,
                tint: (snapshot.batteryPercent ?? 100) < 20 ? .red : .green,
                history: []
            )
        }
    }

    private func tint(for value: Double, warn: Double, critical: Double) -> Color {
        if value >= critical { return .red }
        if value >= warn { return .orange }
        return .green
    }
}
