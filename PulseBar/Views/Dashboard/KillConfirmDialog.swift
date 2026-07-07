import SwiftUI

struct KillConfirmDialog: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vm: PulseBarViewModel
    let row: ProcessRow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header — icon + name + ID
            HStack(alignment: .top, spacing: 12) {
                ProcessIconView(row: row, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quit “\(row.name)”?")
                        .font(.title3.weight(.bold))
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            // Quick stats grid
            HStack(spacing: 0) {
                statColumn("CPU", value: NumberFormatting.percent(row.cpuPercent))
                divider
                statColumn("Memory", value: ByteFormatting.memory(row.memoryBytes))
                divider
                statColumn("Uptime", value: row.uptimeString ?? "—")
                if !row.ports.isEmpty {
                    divider
                    statColumn("Ports",
                               value: row.ports.prefix(3).map(String.init).joined(separator: ", "))
                }
            }
            .padding(.vertical, 12)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if isLikelySystemProcess {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("This looks like a system process. Quitting it may make your Mac unstable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Tip
            Text("Try **Quit** first. If it doesn't respond, use **Force Quit** — unsaved work may be lost.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Actions — Graceful Quit is the prominent default; Force Quit is secondary.
            HStack(spacing: 10) {
                Button("Cancel") { vm.cancelKill() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)

                Spacer()

                Button("Force Quit") { vm.forceQuitSelected() }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .help("Immediately terminate. Unsaved work is lost.")

                Button("Quit") { vm.gracefulQuitSelected() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .help("Politely ask the process to exit. (Safer.)")
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    // MARK: - Helpers

    private var headerSubtitle: String {
        var parts: [String] = []
        if let bid = row.bundleIdentifier { parts.append(bid) }
        parts.append("PID \(row.pid)")
        return parts.joined(separator: " · ")
    }

    /// Rough heuristic — system daemons tend to live in /System/ or /usr/libexec/.
    /// PIDs below 100 are also usually launchd-managed core services.
    private var isLikelySystemProcess: Bool {
        if row.pid < 100 { return true }
        if let path = row.executablePath {
            if path.hasPrefix("/System/") { return true }
            if path.hasPrefix("/usr/libexec/") { return true }
            if path.hasPrefix("/usr/sbin/") { return true }
        }
        return false
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 1, height: 28)
    }

    private func statColumn(_ label: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.callout.monospacedDigit().weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
