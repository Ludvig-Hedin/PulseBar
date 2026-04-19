import SwiftUI
import AppKit

struct MenuBarRootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vm: PulseBarViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(PreferencesService.Key.pauseNotifications) private var pauseNotifications: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with quick actions
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PulseBar")
                        .font(.headline)
                    Text("Activity Monitor, but usable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    pauseNotifications.toggle()
                } label: {
                    Image(systemName: pauseNotifications ? "bell.slash" : "bell")
                }
                .help(pauseNotifications ? "Notifications paused — click to resume" : "Pause notifications")
                .buttonStyle(.borderless)

                Button {
                    vm.refresh(full: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh now")
                .buttonStyle(.borderless)
            }

            // Primary stats — with progress bars so severity is visible at a glance.
            VStack(spacing: 8) {
                MetricBarRow(
                    title: "CPU",
                    value: NumberFormatting.percent(vm.snapshot.cpuUsagePercent),
                    percent: vm.snapshot.cpuUsagePercent / 100,
                    tint: tint(for: vm.snapshot.cpuUsagePercent, warn: 60, critical: 85)
                )
                MetricBarRow(
                    title: "RAM",
                    value: "\(ByteFormatting.gigabytes(vm.snapshot.memoryUsedBytes)) · \(Int(vm.snapshot.memoryUsedPercent))%",
                    percent: vm.snapshot.memoryUsedRatio,
                    tint: tint(for: vm.snapshot.memoryUsedPercent, warn: 70, critical: 85)
                )
                HStack {
                    MiniMetricRow(title: "↓", value: ByteFormatting.rate(vm.snapshot.networkDownloadBytesPerSecond), subtitle: "down")
                    MiniMetricRow(title: "↑", value: ByteFormatting.rate(vm.snapshot.networkUploadBytesPerSecond), subtitle: "up")
                }
                if let batt = vm.snapshot.batteryPercent {
                    MiniMetricRow(
                        title: vm.snapshot.batteryIsCharging ? "Battery ⚡︎" : "Battery",
                        value: NumberFormatting.percent(batt),
                        subtitle: vm.snapshot.batteryMinutesRemaining.map { "\($0) min left" }
                            ?? (vm.snapshot.batteryIsCharging ? "Charging" : "On battery")
                    )
                }
            }

            Divider()

            // Top strain list with app icons (the #1 reason users open the menu)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Top strain")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(vm.snapshot.devServerCount) dev · \(vm.snapshot.runningProcessCount) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(vm.processes.sorted(by: { $0.cpuPercent > $1.cpuPercent }).prefix(5)) { row in
                    HStack(spacing: 8) {
                        ProcessIconView(row: row, size: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.name).lineLimit(1)
                            Text(row.isLikelyDevServer
                                 ? "\(row.devServerKind ?? "Dev") · \(row.ports.map(String.init).joined(separator: ", "))"
                                 : row.kind.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(NumberFormatting.percent(row.cpuPercent))
                            .monospacedDigit()
                            .font(.caption)
                    }
                }
            }

            if !vm.alerts.isEmpty {
                Divider()
                ForEach(vm.alerts.prefix(3)) { alert in
                    HStack(spacing: 8) {
                        Image(systemName: alert.level == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                            .foregroundStyle(alert.level == .critical ? .red : .orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(alert.title).font(.caption.weight(.medium))
                            Text(alert.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button("Dashboard") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("d", modifiers: [.command])

                Button("Settings…") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(",", modifiers: [.command])

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("q", modifiers: [.command])
            }
        }
        .padding(16)
    }

    /// Picks a tint color based on severity thresholds.
    private func tint(for value: Double, warn: Double, critical: Double) -> Color {
        if value >= critical { return .red }
        if value >= warn { return .orange }
        return .green
    }
}

/// A metric row with an embedded progress bar, used only inside the menu bar.
private struct MetricBarRow: View {
    let title: String
    let value: String
    let percent: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.caption.monospacedDigit()).fontWeight(.medium)
            }
            ProgressView(value: max(0, min(1, percent)))
                .tint(tint)
        }
    }
}
