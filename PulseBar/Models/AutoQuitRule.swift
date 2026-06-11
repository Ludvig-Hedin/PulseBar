import Foundation

/// A user-defined rule that automatically quits runaway processes.
///
/// Common case: zombie `node` / `bun` / `python` shells left behind by ad-hoc
/// dev sessions that keep eating CPU or RAM. The user defines a name match
/// plus minimum CPU / memory / uptime thresholds. If a process keeps meeting
/// the thresholds for `sustainedSeconds`, it is quit automatically.
struct AutoQuitRule: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String

    /// Whether this rule fires.
    var enabled: Bool = true

    /// Case-insensitive substring match on process name or executable path.
    /// Empty string = ignored.
    var nameContains: String

    /// Optional path-prefix match (case-insensitive `contains`). Empty = ignored.
    var pathContains: String = ""

    /// Minimum CPU% for the process to qualify. 0 = ignored.
    var minCpuPercent: Double = 0

    /// Minimum resident memory (in MB) for the process to qualify. 0 = ignored.
    var minMemoryMB: Double = 0

    /// Process must have been alive at least this long before the rule applies.
    /// Protects newly-launched dev servers from being killed during warmup.
    var minUptimeSeconds: Int = 60

    /// Process must keep matching the thresholds for this long before being quit.
    /// Prevents one-off CPU spikes from triggering a kill.
    var sustainedSeconds: Int = 60

    /// If true, force-terminate instead of graceful quit.
    var force: Bool = false

    /// Helpful preset for the "zombie dev server" use case the user described.
    static var zombieNodeBunPreset: AutoQuitRule {
        AutoQuitRule(
            name: "Idle node/bun shells",
            enabled: false,
            nameContains: "node",
            pathContains: "",
            minCpuPercent: 50,
            minMemoryMB: 0,
            minUptimeSeconds: 300,
            sustainedSeconds: 120,
            force: false
        )
    }
}

/// One row in the auto-quit history shown to the user in Settings.
struct AutoQuitEvent: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let processName: String
    let pid: Int32
    let ruleName: String
    let action: Action

    enum Action: String, Codable {
        case graceful
        case force
        case skipped // matched but blocked by safety guard
    }
}
