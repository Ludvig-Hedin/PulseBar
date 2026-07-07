import SwiftUI

struct OverviewSection: View {
    @EnvironmentObject private var vm: PulseBarViewModel
    @EnvironmentObject private var storageVM: StorageViewModel
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
            if let batt = snapshot.batteryPercent {
                MetricCard(
                    title: "Battery",
                    icon: snapshot.batteryIsCharging ? "battery.100.bolt" : "battery.75",
                    value: NumberFormatting.percent(batt),
                    subtitle: snapshot.batteryMinutesRemaining.map { "\($0) min left" }
                        ?? (snapshot.batteryIsCharging ? "Charging" : "On battery"),
                    progress: batt / 100,
                    tint: batt < 20 ? .red : .green,
                    history: []
                )
            }
            if let usage = storageVM.diskUsage {
                MetricCard(
                    title: "Storage",
                    icon: "internaldrive.fill",
                    value: NumberFormatting.percent(usage.usedPercent),
                    subtitle: "\(usage.freeFormatted) free of \(usage.totalFormatted)",
                    progress: usage.usedRatio,
                    tint: tint(for: usage.usedPercent, warn: 70, critical: 85),
                    history: []
                )
            }
        }
    }

    private func tint(for value: Double, warn: Double, critical: Double) -> Color {
        if value >= critical { return .red }
        if value >= warn { return .orange }
        return .green
    }
}
