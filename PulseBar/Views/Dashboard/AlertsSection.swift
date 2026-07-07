import SwiftUI

struct AlertsSection: View {
    @EnvironmentObject private var vm: PulseBarViewModel
    let alerts: [AlertItem]
    /// Optional deep-link — when provided, alert cards show a CTA that navigates
    /// to the Processes tab (caller decides what that means).
    var onShowProcesses: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Alerts")
                    .font(.title3.weight(.semibold))
                Spacer()
                if !alerts.isEmpty {
                    Text("\(alerts.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                }
            }

            if alerts.isEmpty {
                EmptyStateView(title: "All clear", subtitle: "No alerts in the last few minutes.")
            } else {
                VStack(spacing: 10) {
                    ForEach(alerts) { alert in
                        AlertCard(alert: alert, onShowProcesses: onShowProcesses)
                            .environmentObject(vm)
                    }
                }
            }
        }
    }
}

private struct AlertCard: View {
    @EnvironmentObject private var vm: PulseBarViewModel
    let alert: AlertItem
    let onShowProcesses: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 6) {
                Text(alert.title).font(.headline)
                Text(alert.subtitle).foregroundStyle(.secondary)

                if let hint = suggestion(for: alert) {
                    Label(hint, systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                // Inline CTA — actionable alerts (CPU/RAM) get a "View processes" button.
                if let cta = ctaLabel, let onShowProcesses {
                    Button(cta) {
                        // Pre-filter Processes to the most useful subset for this alert.
                        if alert.title.lowercased().contains("ram")
                            || alert.title.lowercased().contains("memory")
                            || alert.title.lowercased().contains("cpu") {
                            vm.filter = .heavy
                            vm.sortColumn = alert.title.lowercased().contains("cpu") ? .cpu : .memory
                            vm.sortDirection = .descending
                        }
                        onShowProcesses()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(.thinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16).strokeBorder(color.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var icon: String {
        switch alert.level {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.circle"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch alert.level {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var ctaLabel: String? {
        let t = alert.title.lowercased()
        if t.contains("cpu") { return "Show top CPU offenders" }
        if t.contains("ram") || t.contains("memory") { return "Show top memory offenders" }
        return nil
    }

    private func suggestion(for alert: AlertItem) -> String? {
        let t = alert.title.lowercased()
        if t.contains("cpu") { return "Quit the heaviest process to bring usage down." }
        if t.contains("ram") || t.contains("memory") { return "Quit apps you aren't using, or restart heavy dev servers." }
        if t.contains("battery") { return "Plug in, or close battery-hungry apps like browsers." }
        return nil
    }
}
