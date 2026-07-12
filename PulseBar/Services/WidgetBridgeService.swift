import Foundation
import WidgetKit

/// Publishes live app state to the widget extension via the App Group.
///
/// Writing to `UserDefaults` is cheap and happens on every refresh tick, but
/// `WidgetCenter.reloadAllTimelines()` spends the OS's widget-refresh budget,
/// so it's throttled: a 15s floor between reloads, gated on a change the user
/// would actually notice, plus a 5-minute heartbeat so a stale/"open PulseBar"
/// indicator in the widget always clears eventually even if readings are flat.
@MainActor
final class WidgetBridgeService {
    static let shared = WidgetBridgeService()

    private var lastReloadAt: Date = .distantPast
    private var lastReloadedSnapshot: WidgetSnapshot?

    private let minReloadInterval: TimeInterval = 15
    private let heartbeatInterval: TimeInterval = 300

    private init() {}

    func publish(_ snapshot: WidgetSnapshot) {
        WidgetSnapshotStore.write(snapshot)

        let now = Date()
        let changed = lastReloadedSnapshot.map { significantChange(from: $0, to: snapshot) } ?? true
        let intervalOK = now.timeIntervalSince(lastReloadAt) >= minReloadInterval
        let heartbeatDue = now.timeIntervalSince(lastReloadAt) >= heartbeatInterval

        guard (changed && intervalOK) || heartbeatDue else { return }
        lastReloadAt = now
        lastReloadedSnapshot = snapshot
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func significantChange(from a: WidgetSnapshot, to b: WidgetSnapshot) -> Bool {
        abs(a.cpuPercent - b.cpuPercent) >= 3
            || (a.ramUsedBytes > b.ramUsedBytes ? a.ramUsedBytes - b.ramUsedBytes : b.ramUsedBytes - a.ramUsedBytes) > 200_000_000
            || a.diskUsedBytes != b.diskUsedBytes
            || a.devServers.map(\.id) != b.devServers.map(\.id)
            || a.topProcesses.first?.pid != b.topProcesses.first?.pid
    }
}
