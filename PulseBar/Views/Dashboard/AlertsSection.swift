import SwiftUI

struct AlertsSection: View {
    let alerts: [AlertItem]

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
                EmptyStateView(title: "No active alerts", subtitle: "Your Mac is behaving. Miracles happen.")
            } else {
                VStack(spacing: 10) {
                    ForEach(alerts) { alert in
                        AlertCard(alert: alert)
                    }
                }
            }
        }
    }
}

private struct AlertCard: View {
    let alert: AlertItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title).font(.headline)
                Text(alert.subtitle).foregroundStyle(.secondary)
                // Actionable hint — the #1 ask of any "Activity Monitor replacement".
                if let hint = Self.suggestion(for: alert) {
                    Label(hint, systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
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

    private static func suggestion(for alert: AlertItem) -> String? {
        let t = alert.title.lowercased()
        if t.contains("cpu") { return "Switch to the Processes tab and quit the top offender." }
        if t.contains("ram") || t.contains("memory") { return "Quit apps you aren't using, or restart heavy dev servers." }
        if t.contains("battery") { return "Plug in, or close battery-hungry apps like browsers." }
        return nil
    }
}
