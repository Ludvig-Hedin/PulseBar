import SwiftUI

struct ProcessRowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vm: PulseBarViewModel
    let row: ProcessRow

    private var isSelected: Bool { vm.selectedProcessPIDs.contains(row.pid) }

    var body: some View {
        HStack(spacing: 14) {

            // ── Select checkbox (shown only in select mode) ──────────────────
            if vm.isSelectMode {
                Button {
                    vm.toggleSelection(row.pid)
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 24)
            }

            // ── Name ─────────────────────────────────────────────────────────
            HStack(spacing: 10) {
                ProcessIconView(row: row, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .font(.body.weight(.medium))
                        if row.isLikelyDevServer {
                            Text(row.devServerKind ?? "Dev")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                        if row.isFrontmost {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                                .help("Frontmost app")
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Tapping the name area also toggles selection in select mode
            .contentShape(Rectangle())
            .onTapGesture {
                if vm.isSelectMode { vm.toggleSelection(row.pid) }
            }

            // ── CPU ──────────────────────────────────────────────────────────
            if vm.visibleColumns.contains(.cpu) {
                Text(NumberFormatting.percent(row.cpuPercent))
                    .frame(width: 80, alignment: .trailing)
                    .monospacedDigit()
                    .foregroundStyle(cpuTint)
            }

            // ── Memory ───────────────────────────────────────────────────────
            if vm.visibleColumns.contains(.memory) {
                Text(ByteFormatting.memory(row.memoryBytes))
                    .frame(width: 110, alignment: .trailing)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // ── Uptime ───────────────────────────────────────────────────────
            if vm.visibleColumns.contains(.uptime) {
                Text(row.uptimeString ?? "—")
                    .frame(width: 70, alignment: .trailing)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // ── Ports (left of Actions) ──────────────────────────────────────
            if vm.visibleColumns.contains(.ports) {
                Text(row.ports.isEmpty ? "—" : row.ports.prefix(3).map(String.init).joined(separator: ", "))
                    .frame(width: 120, alignment: .leading)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // ── Kill button ──────────────────────────────────────────────────
            Button("Kill") {
                vm.requestKill(row)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(width: 90)
            .disabled(row.pid == Int32(ProcessInfo.processInfo.processIdentifier))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // Highlight when selected
        .background(
            isSelected && vm.isSelectMode
                ? Color.accentColor.opacity(0.08)
                : Color.clear
        )
        .contextMenu {
            Button("Bring to Front") { vm.activateApp(row) }
                .disabled(row.kind != .app)
            Button("Reveal in Finder") { vm.revealInFinder(row) }
                .disabled(row.executablePath == nil)
            Button("Copy PID") { vm.copyPID(row) }
            Divider()
            Button("Graceful Quit", role: .destructive) { vm.requestKill(row) }
                .disabled(row.pid == Int32(ProcessInfo.processInfo.processIdentifier))
        }
    }

    private var subtitle: String {
        if row.isLikelyDevServer {
            let label = row.devServerKind ?? "Dev server"
            return row.executablePath.map { "\(label) · \($0)" } ?? label
        }
        return row.bundleIdentifier ?? row.executablePath ?? row.kind.rawValue
    }

    /// Colour the CPU column so hotspots are obvious without reading the digits.
    private var cpuTint: Color {
        if row.cpuPercent >= 80 { return .red }
        if row.cpuPercent >= 40 { return .orange }
        return .primary
    }
}
