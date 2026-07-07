import SwiftUI

/// Compact "what should I look at?" panel for the Overview tab.
/// Shows the top 5 CPU offenders and top 5 RAM offenders side-by-side,
/// with a hover-reveal Quit affordance on each row. Replaces the previous
/// duplicated ProcessesSection embed so Overview has its own identity.
struct TopActivitySection: View {
    @EnvironmentObject private var vm: PulseBarViewModel
    @EnvironmentObject private var appState: AppState
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top activity")
                    .font(.title3.weight(.semibold))
                Spacer()
                if let onSeeAll {
                    Button("See all processes") {
                        vm.filter = .all
                        onSeeAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Switch to the Processes tab to see the full table")
                }
            }

            HStack(alignment: .top, spacing: 16) {
                TopActivityCard(
                    title: "By CPU",
                    icon: "cpu",
                    rows: Array(vm.processes.sorted(by: { $0.cpuPercent > $1.cpuPercent }).prefix(5)),
                    metricLabel: { NumberFormatting.percent($0.cpuPercent) },
                    metricTint: { row in
                        if row.cpuPercent >= 80 { return .red }
                        if row.cpuPercent >= 40 { return .orange }
                        return .primary
                    }
                )
                TopActivityCard(
                    title: "By Memory",
                    icon: "memorychip",
                    rows: Array(vm.processes.sorted(by: { $0.memoryBytes > $1.memoryBytes }).prefix(5)),
                    metricLabel: { ByteFormatting.memory($0.memoryBytes) },
                    metricTint: { _ in .secondary }
                )
            }
        }
    }
}

private struct TopActivityCard: View {
    let title: String
    let icon: String
    let rows: [ProcessRow]
    let metricLabel: (ProcessRow) -> String
    let metricTint: (ProcessRow) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text("Gathering process data…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ForEach(rows) { row in
                    TopActivityRow(row: row,
                                   metricLabel: metricLabel(row),
                                   metricTint: metricTint(row))
                    if row.id != rows.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TopActivityRow: View {
    @EnvironmentObject private var vm: PulseBarViewModel
    let row: ProcessRow
    let metricLabel: String
    let metricTint: Color
    @State private var hover = false

    private var isSelf: Bool { row.pid == Int32(ProcessInfo.processInfo.processIdentifier) }

    var body: some View {
        HStack(spacing: 10) {
            ProcessIconView(row: row, size: 22)
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
                    vm.requestKill(row)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Quit \(row.name)")
            }
            Text(metricLabel)
                .monospacedDigit()
                .font(.callout.weight(.medium))
                .foregroundStyle(metricTint)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hover ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            if row.kind == .app { vm.activateApp(row) }
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
}
