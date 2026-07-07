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
            header

            if pauseNotifications {
                PausedRibbon { pauseNotifications = false }
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

            // Top strain — click to bring app to front; hover to reveal Quit.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Top strain")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(vm.snapshot.devServerCount) dev · \(vm.snapshot.runningProcessCount) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let top = vm.processes.sorted(by: { $0.cpuPercent > $1.cpuPercent }).prefix(5)
                if top.isEmpty {
                    Text("Gathering process data…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(Array(top)) { row in
                        TopStrainRow(row: row)
                            .environmentObject(vm)
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
                        Spacer()
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Open Dashboard", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("d", modifiers: [.command])
                .help("Open the full dashboard (⌘D)")

                Button {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(",", modifiers: [.command])
                .help("Settings (⌘,)")

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("q", modifiers: [.command])
                .help("Quit PulseBar (⌘Q)")
            }
        }
        .padding(16)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PulseBar")
                    .font(.headline)
                Text("Live system monitor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                pauseNotifications.toggle()
            } label: {
                Image(systemName: pauseNotifications ? "bell.slash.fill" : "bell")
                    .foregroundStyle(pauseNotifications ? .orange : .primary)
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
    }

    /// Picks a tint color based on severity thresholds.
    private func tint(for value: Double, warn: Double, critical: Double) -> Color {
        if value >= critical { return .red }
        if value >= warn { return .orange }
        return .green
    }
}

// MARK: - Paused ribbon
private struct PausedRibbon: View {
    var resume: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.orange)
            Text("Notifications paused")
                .font(.caption.weight(.medium))
            Spacer()
            Button("Resume", action: resume)
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Top strain row (clickable + hover-reveal Quit)
private struct TopStrainRow: View {
    @EnvironmentObject private var vm: PulseBarViewModel
    @Environment(\.openWindow) private var openWindow
    let row: ProcessRow
    @State private var hover = false

    private var isSelf: Bool { row.pid == Int32(ProcessInfo.processInfo.processIdentifier) }

    var body: some View {
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
            if hover && !isSelf {
                Button {
                    requestQuit()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Quit \(row.name)")
            }
            Text(NumberFormatting.percent(row.cpuPercent))
                .monospacedDigit()
                .font(.caption)
                .foregroundStyle(cpuTint)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hover ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            if row.kind == .app {
                vm.activateApp(row)
            }
        }
        .contextMenu {
            Button("Bring to Front") { vm.activateApp(row) }
                .disabled(row.kind != .app)
            Button("Reveal in Finder") { vm.revealInFinder(row) }
                .disabled(row.executablePath == nil)
            Button("Copy PID") { vm.copyPID(row) }
            Divider()
            Button("Quit", role: .destructive) { requestQuit() }
                .disabled(isSelf)
        }
    }

    /// Opens the dashboard (so the kill-confirm sheet has a host) and requests the kill.
    private func requestQuit() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        vm.requestKill(row)
    }

    private var cpuTint: Color {
        if row.cpuPercent >= 80 { return .red }
        if row.cpuPercent >= 40 { return .orange }
        return .primary
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
