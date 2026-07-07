import Foundation

/// Evaluates auto-quit rules against the live process list. Tracks per-PID
/// "first matched at" timestamps so the `sustainedSeconds` requirement is
/// honored across refresh ticks. Will refuse to touch PulseBar itself or any
/// process that looks like a core system daemon.
@MainActor
final class AutoQuitService {
    /// Most recent events (most recent last). Bounded to prevent unbounded growth.
    private(set) var recentEvents: [AutoQuitEvent] = []
    private let maxEvents = 50

    /// pid → first instant the process started matching any rule.
    private var firstMatchedAt: [Int32: Date] = [:]

    private let killService = KillService()

    /// Run rules against the latest process snapshot. Returns the events fired
    /// during this evaluation so callers can surface notifications, etc.
    @discardableResult
    func evaluate(rules: [AutoQuitRule], processes: [ProcessRow]) -> [AutoQuitEvent] {
        let enabledRules = rules.filter(\.enabled)
        guard !enabledRules.isEmpty else {
            firstMatchedAt.removeAll()
            return []
        }

        let now = Date()
        var fired: [AutoQuitEvent] = []
        var stillQualifying: Set<Int32> = []

        for proc in processes {
            guard let rule = enabledRules.first(where: { matches(rule: $0, proc: proc) }) else { continue }
            stillQualifying.insert(proc.pid)

            // Bookkeeping: remember when the process first qualified.
            let firstAt: Date
            if let existing = firstMatchedAt[proc.pid] {
                firstAt = existing
            } else {
                firstAt = now
                firstMatchedAt[proc.pid] = now
            }

            let sustained = now.timeIntervalSince(firstAt)
            guard sustained >= Double(rule.sustainedSeconds) else { continue }

            // Safety net before issuing a kill.
            guard isSafeToKill(proc: proc) else {
                fired.append(.init(
                    timestamp: now,
                    processName: proc.name,
                    pid: proc.pid,
                    ruleName: rule.name,
                    action: .skipped
                ))
                firstMatchedAt[proc.pid] = nil
                continue
            }

            let action: AutoQuitEvent.Action
            if rule.force {
                _ = killService.forceQuit(pid: proc.pid)
                action = .force
            } else {
                _ = killService.gracefulQuit(pid: proc.pid)
                action = .graceful
            }
            fired.append(.init(
                timestamp: now,
                processName: proc.name,
                pid: proc.pid,
                ruleName: rule.name,
                action: action
            ))
            firstMatchedAt[proc.pid] = nil
        }

        // Drop matches that no longer qualify so a process that calms down isn't
        // killed when it spikes again later.
        firstMatchedAt = firstMatchedAt.filter { stillQualifying.contains($0.key) }

        if !fired.isEmpty {
            recentEvents.append(contentsOf: fired)
            if recentEvents.count > maxEvents {
                recentEvents.removeFirst(recentEvents.count - maxEvents)
            }
        }

        return fired
    }

    func clearEvents() {
        recentEvents.removeAll()
    }

    // MARK: - Matching

    private func matches(rule: AutoQuitRule, proc: ProcessRow) -> Bool {
        // Name / path match.
        if !rule.nameContains.isEmpty {
            let hayName = proc.name
            let hayPath = proc.executablePath ?? ""
            if !hayName.localizedCaseInsensitiveContains(rule.nameContains)
                && !hayPath.localizedCaseInsensitiveContains(rule.nameContains) {
                return false
            }
        }
        if !rule.pathContains.isEmpty {
            guard proc.executablePath?.localizedCaseInsensitiveContains(rule.pathContains) ?? false else {
                return false
            }
        }

        // Uptime gate (protects warmup).
        if rule.minUptimeSeconds > 0 {
            guard let launch = proc.launchDate else { return false }
            if Date().timeIntervalSince(launch) < Double(rule.minUptimeSeconds) { return false }
        }

        // Resource thresholds. If both are set, OR them together so either signal triggers.
        // If only one is set, it must meet. If neither is set, the rule still matches by name —
        // this lets the user write "any process named ngrok older than 10 minutes" rules.
        let cpuConfigured = rule.minCpuPercent > 0
        let memConfigured = rule.minMemoryMB > 0
        let memUsageMB = Double(proc.memoryBytes) / 1_048_576

        switch (cpuConfigured, memConfigured) {
        case (false, false): return true
        case (true, false): return proc.cpuPercent >= rule.minCpuPercent
        case (false, true): return memUsageMB >= rule.minMemoryMB
        case (true, true): return proc.cpuPercent >= rule.minCpuPercent || memUsageMB >= rule.minMemoryMB
        }
    }

    /// Hard refusal to touch PulseBar itself or anything that looks like a system daemon.
    private func isSafeToKill(proc: ProcessRow) -> Bool {
        if proc.pid == Int32(ProcessInfo.processInfo.processIdentifier) { return false }
        if proc.pid < 100 { return false }
        if let path = proc.executablePath {
            if path.hasPrefix("/System/") { return false }
            if path.hasPrefix("/usr/libexec/") { return false }
            if path.hasPrefix("/usr/sbin/") { return false }
            if path.hasPrefix("/sbin/") { return false }
        }
        return true
    }
}
