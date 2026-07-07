import SwiftUI
import AppKit

struct ProcessRowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vm: PulseBarViewModel
    let row: ProcessRow

    private var isSelected: Bool { vm.selectedProcessPIDs.contains(row.pid) }
    private var isSelf: Bool { row.pid == Int32(ProcessInfo.processInfo.processIdentifier) }

    var body: some View {
        HStack(spacing: 14) {

            // ── Select checkbox (shown only in select mode) ──────────────────
            if vm.isSelectMode {
                Button {
                    selectWithCurrentModifiers()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 24)
                .help("Click to toggle. Shift-click to extend the selection. ⌘-click to toggle individually.")
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
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                                .help("Detected as a dev server")
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
                        .help(subtitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Tapping the name area also toggles selection in select mode (shift/cmd aware).
            .contentShape(Rectangle())
            .onTapGesture {
                if vm.isSelectMode { selectWithCurrentModifiers() }
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

            // ── Ports ────────────────────────────────────────────────────────
            if vm.visibleColumns.contains(.ports) {
                portsCell
                    .frame(width: 120, alignment: .leading)
            }

            // ── Quit button ──────────────────────────────────────────────────
            Button("Quit") {
                vm.requestKill(row)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(width: 90)
            .disabled(isSelf)
            .help(isSelf ? "PulseBar cannot quit itself" : "Quit \(row.name)")
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
            Button("Quit", role: .destructive) { vm.requestKill(row) }
                .disabled(isSelf)
        }
    }

    /// Ports list with "+N" overflow indicator and a tooltip showing every port.
    private var portsCell: some View {
        Group {
            if row.ports.isEmpty {
                Text("—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                let visible = row.ports.prefix(3).map(String.init).joined(separator: ", ")
                let extra = row.ports.count - 3
                HStack(spacing: 4) {
                    Text(visible)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if extra > 0 {
                        Text("+\(extra)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }
                .help(row.ports.map(String.init).joined(separator: ", "))
            }
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

    /// Reads the current modifier flags so shift-click extends a contiguous range and
    /// cmd-click toggles a single row (matching Finder / Mail conventions).
    private func selectWithCurrentModifiers() {
        let flags = NSEvent.modifierFlags
        vm.selectWithModifiers(
            pid: row.pid,
            shift: flags.contains(.shift),
            command: flags.contains(.command)
        )
    }
}
