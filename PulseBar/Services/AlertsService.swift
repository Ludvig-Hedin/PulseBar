import Foundation

/// Produces the list of in-app alerts shown in the dashboard and menu bar.
/// Notifications (banners) are posted separately by NotificationService — this
/// service is purely for the visual alert list.
@MainActor
final class AlertsService {
    private(set) var items: [AlertItem] = []

    func evaluate(snapshot: SystemSnapshot, processes: [ProcessRow]) -> [AlertItem] {
        var output: [AlertItem] = []
        let prefs = PreferencesService.shared

        // Memory: show the highest RAM threshold that has been crossed so the
        // alert list stays tidy instead of listing every step (50 / 70 / 80 / 90).
        let ramPercent = snapshot.memoryUsedPercent
        if let highest = prefs.ramThresholds.sorted().last(where: { Double($0) <= ramPercent }) {
            let level: AlertItem.Level = highest >= 90 ? .critical : (highest >= 80 ? .warning : .info)
            let topMem = processes.sorted { $0.memoryBytes > $1.memoryBytes }.first
            let subtitle = topMem.map { "Top: \($0.name) — \(ByteFormatting.memory($0.memoryBytes))" }
                ?? "Used \(Int(ramPercent))% of RAM"
            output.append(.init(level: level, title: "RAM at \(highest)%+", subtitle: subtitle))
        } else if snapshot.memoryPressure == .critical {
            output.append(.init(level: .critical, title: "Memory pressure critical", subtitle: "You are close to a bad time."))
        } else if snapshot.memoryPressure == .warning {
            output.append(.init(level: .warning, title: "Memory pressure rising", subtitle: "A few heavy apps are eating RAM."))
        }

        // CPU
        if snapshot.cpuUsagePercent >= Double(prefs.cpuThreshold) {
            let top = processes.sorted { $0.cpuPercent > $1.cpuPercent }.first
            output.append(.init(
                level: snapshot.cpuUsagePercent >= 95 ? .critical : .warning,
                title: "CPU running hot (\(Int(snapshot.cpuUsagePercent))%)",
                subtitle: top.map { "Top: \($0.name) — \(Int($0.cpuPercent))%" } ?? "System-wide CPU spike."
            ))
        }

        // Battery
        if let battery = snapshot.batteryPercent,
           !snapshot.batteryIsCharging,
           battery <= Double(prefs.batteryThreshold) {
            output.append(.init(
                level: battery <= 10 ? .critical : .warning,
                title: "Battery low",
                subtitle: "\(Int(battery))% left. Plug in to keep working."
            ))
        }

        items = output
        return output
    }
}
