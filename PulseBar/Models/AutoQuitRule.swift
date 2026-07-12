import Foundation

/// A user-defined rule that automatically quits runaway processes.
///
/// Common case: zombie `node` / `bun` / `python` shells left behind by ad-hoc
/// dev sessions that keep eating CPU or RAM. The user defines a name match
/// plus minimum CPU / memory / uptime thresholds. If a process keeps meeting
/// the thresholds for `sustainedSeconds`, it is quit automatically.
struct AutoQuitRule: Identifiable, Codable, Hashable {
    /// What has to be true before this rule will quit a matching process.
    enum TriggerMode: String, Codable {
        /// Fires when the matched process's own CPU%/memory/uptime cross the thresholds below.
        case processUsage
        /// Fires when the whole system is under memory/CPU pressure, regardless of what this
        /// one process is doing on its own.
        case systemPressure
    }

    var id: UUID = UUID()
    var name: String

    /// Whether this rule fires.
    var enabled: Bool = true

    /// Which condition has to be true before this rule quits a matching process.
    var triggerMode: TriggerMode = .processUsage

    /// Case-insensitive substring match on process name or executable path.
    /// Empty string = ignored.
    var nameContains: String

    /// Optional path-prefix match (case-insensitive `contains`). Empty = ignored.
    var pathContains: String = ""

    /// Minimum CPU% for the process to qualify. 0 = ignored. Used by `.processUsage` rules.
    var minCpuPercent: Double = 0

    /// Minimum resident memory (in MB) for the process to qualify. 0 = ignored. Used by `.processUsage` rules.
    var minMemoryMB: Double = 0

    /// System-wide free-memory percent below which a `.systemPressure` rule fires. 0 = ignored.
    var sysFreeMemoryBelowPercent: Double = 0

    /// System-wide free memory (in GB) below which a `.systemPressure` rule fires. 0 = ignored.
    var sysFreeMemoryBelowGB: Double = 0

    /// System-wide CPU% above which a `.systemPressure` rule fires. 0 = ignored.
    var sysCPUAbovePercent: Double = 0

    /// Process must have been alive at least this long before the rule applies.
    /// Protects newly-launched dev servers from being killed during warmup.
    var minUptimeSeconds: Int = 60

    /// For `.processUsage`: process must keep matching the thresholds this long before being quit.
    /// For `.systemPressure`: the system must stay under pressure this long before anything is quit.
    /// Either way, prevents one-off spikes from triggering a kill.
    var sustainedSeconds: Int = 60

    /// If true, force-terminate instead of graceful quit.
    var force: Bool = false

    /// Helpful preset for the "zombie dev server" use case the user described.
    static var zombieNodeBunPreset: AutoQuitRule {
        AutoQuitRule(
            name: "Idle node/bun shells",
            enabled: false,
            triggerMode: .processUsage,
            nameContains: "node",
            pathContains: "",
            minCpuPercent: 50,
            minMemoryMB: 0,
            minUptimeSeconds: 300,
            sustainedSeconds: 120,
            force: false
        )
    }

    /// Helpful preset for freeing RAM under memory pressure. Ships disabled and with no target
    /// app name — the user picks one via the running-app picker in the rule editor.
    static var lowMemoryPreset: AutoQuitRule {
        AutoQuitRule(
            name: "Quit app when RAM is low",
            enabled: false,
            triggerMode: .systemPressure,
            nameContains: "",
            sysFreeMemoryBelowPercent: 10,
            minUptimeSeconds: 0,
            sustainedSeconds: 30,
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
