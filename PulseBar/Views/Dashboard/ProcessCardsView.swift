import SwiftUI
import AppKit

/// Grid of process cards — an alternate, denser-than-table view of the same data.
/// Useful when scanning visually for apps you recognise by icon (e.g. "what's that orange one
/// eating my CPU?"). Toggleable from the Processes header.
struct ProcessCardsView: View {
    @EnvironmentObject private var vm: PulseBarViewModel
    @EnvironmentObject private var appState: AppState

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14)]

    var body: some View {
        if vm.filteredProcesses.isEmpty {
            EmptyStateView(
                title: "No processes match",
                subtitle: "Try a different filter or clear your search."
            )
            .padding(20)
        } else {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(vm.filteredProcesses) { row in
                    ProcessCard(row: row)
                        .environmentObject(appState)
                        .environmentObject(vm)
                }
            }
        }
    }
}

private struct ProcessCard: View {
    @EnvironmentObject private var vm: PulseBarViewModel
    let row: ProcessRow

    @State private var hover = false

    private var isSelf: Bool { row.pid == Int32(ProcessInfo.processInfo.processIdentifier) }
    private var isSelected: Bool { vm.selectedProcessPIDs.contains(row.pid) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProcessIconView(row: row, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .font(.headline)
                            .lineLimit(1)
                        if row.isLikelyDevServer {
                            Text(row.devServerKind ?? "Dev")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    Text(row.kind.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if vm.isSelectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
            }

            // Metrics
            HStack(spacing: 14) {
                MetricChip(label: "CPU",
                           value: NumberFormatting.percent(row.cpuPercent),
                           tint: cpuTint)
                MetricChip(label: "MEM",
                           value: ByteFormatting.memory(row.memoryBytes),
                           tint: .secondary)
                if let uptime = row.uptimeString {
                    MetricChip(label: "Up", value: uptime, tint: .secondary)
                }
            }

            if !row.ports.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "network")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(row.ports.prefix(4).map(String.init).joined(separator: ", ")
                         + (row.ports.count > 4 ? "  +\(row.ports.count - 4)" : ""))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack {
                Spacer()
                if hover && !isSelf && !vm.isSelectMode {
                    Button {
                        vm.requestKill(row)
                    } label: {
                        Label("Quit", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }
            .frame(minHeight: 22)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected && vm.isSelectMode
                      ? Color.accentColor.opacity(0.08)
                      : Color.clear)
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isSelected && vm.isSelectMode
                        ? Color.accentColor.opacity(0.5)
                        : Color.secondary.opacity(0.12),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            if vm.isSelectMode {
                let flags = NSEvent.modifierFlags
                vm.selectWithModifiers(pid: row.pid,
                                       shift: flags.contains(.shift),
                                       command: flags.contains(.command))
            } else if row.kind == .app {
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
            Button("Quit", role: .destructive) { vm.requestKill(row) }
                .disabled(isSelf)
        }
    }

    private var cpuTint: Color {
        if row.cpuPercent >= 80 { return .red }
        if row.cpuPercent >= 40 { return .orange }
        return .primary
    }
}

private struct MetricChip: View {
    let label: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
    }
}
