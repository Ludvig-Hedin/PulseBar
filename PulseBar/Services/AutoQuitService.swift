import Foundation

/// Evaluates auto-quit rules against the live process list and system snapshot.
/// `.processUsage` rules track per-PID "first matched at" timestamps; `.systemPressure`
/// rules track per-rule "first met at" timestamps — either way `sustainedSeconds` is honored
/// across refresh ticks before anything is quit. Will refuse to touch PulseBar itself or any
/// process that looks like a core system daemon.
@MainActor
final class AutoQuitService {
    /// Most recent events (most recent last). Bounded to prevent unbounded growth.
    private(set) var recentEvents: [AutoQuitEvent] = []
    private let maxEvents = 50

    /// pid → first instant the process started matching any `.processUsage` rule.
    private var firstMatchedAt: [Int32: Date] = [:]

    /// rule id → first instant that rule's `.systemPressure` condition became true.
    private var systemPressureFirstMetAt: [UUID: Date] = [:]

    private let killService = KillService()

    /// Run rules against the latest process snapshot. Returns the events fired
    /// during this evaluation so callers can surface notifications, etc.
    @discardableResult
    func evaluate(rules: [AutoQuitRule], processes: [ProcessRow], snapshot: SystemSnapshot) -> [AutoQuitEvent] {
        let enabledRules = rules.filter(\.enabled)
        guard !enabledRules.isEmpty else {
            firstMatchedAt.removeAll()
            systemPressureFirstMetAt.removeAll()
            return []
        }

        let now = Date()
        var fired: [AutoQuitEvent] = []

        fired.append(contentsOf: evaluateProcessUsageRules(
            enabledRules.filter { $0.triggerMode == .processUsage },
            processes: processes,
            now: now
        ))
        fired.append(contentsOf: evaluateSystemPressureRules(
            enabledRules.filter { $0.triggerMode == .systemPressure },
            processes: processes,
            snapshot: snapshot,
            now: now
        ))

        if !fired.isEmpty {
            recentEvents.append(contentsOf: fired)
            if recentEvents.count > maxEvents {
                recentEvents.removeFirst(recentEvents.count - maxEvents)
            }
        }

        return fired
    }

    private func evaluateProcessUsageRules(_ rules: [AutoQuitRule], processes: [ProcessRow], now: Date) -> [AutoQuitEvent] {
        guard !rules.isEmpty else {
            firstMatchedAt.removeAll()
            return []
        }

        var fired: [AutoQuitEvent] = []
        var stillQualifying: Set<Int32> = []

        for proc in processes {
            guard let rule = rules.first(where: { matches(rule: $0, proc: proc) }) else { continue }
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

            fired.append(quit(proc: proc, rule: rule, now: now))
            firstMatchedAt[proc.pid] = nil
        }

        // Drop matches that no longer qualify so a process that calms down isn't
        // killed when it spikes again later.
        firstMatchedAt = firstMatchedAt.filter { stillQualifying.contains($0.key) }

        return fired
    }

    private func evaluateSystemPressureRules(
        _ rules: [AutoQuitRule],
        processes: [ProcessRow],
        snapshot: SystemSnapshot,
        now: Date
    ) -> [AutoQuitEvent] {
        guard !rules.isEmpty else {
            systemPressureFirstMetAt.removeAll()
            return []
        }

        var fired: [AutoQuitEvent] = []
        var activeRuleIDs: Set<UUID> = []

        for rule in rules {
            guard systemPressureConditionMet(rule: rule, snapshot: snapshot) else { continue }
            activeRuleIDs.insert(rule.id)

            let firstAt = systemPressureFirstMetAt[rule.id] ?? now
            systemPressureFirstMetAt[rule.id] = firstAt

            let sustained = now.timeIntervalSince(firstAt)
            guard sustained >= Double(rule.sustainedSeconds) else { continue }

            for proc in processes {
                guard targetMatches(rule: rule, proc: proc) else { continue }
                if rule.minUptimeSeconds > 0 {
                    guard let launch = proc.launchDate,
                          now.timeIntervalSince(launch) >= Double(rule.minUptimeSeconds) else { continue }
                }
                fired.append(quit(proc: proc, rule: rule, now: now))
            }
        }

        // Drop rules whose pressure condition no longer holds so a system that recovers
        // doesn't immediately re-trigger the moment it spikes again.
        systemPressureFirstMetAt = systemPressureFirstMetAt.filter { activeRuleIDs.contains($0.key) }

        return fired
    }

    /// Runs the safety guard and issues the kill. Always returns an event — `.skipped` if the
    /// safety guard blocked it, `.graceful`/`.force` otherwise.
    private func quit(proc: ProcessRow, rule: AutoQuitRule, now: Date) -> AutoQuitEvent {
        guard isSafeToKill(proc: proc) else {
            return .init(
                timestamp: now,
                processName: proc.name,
                pid: proc.pid,
                ruleName: rule.name,
                action: .skipped
            )
        }

        let action: AutoQuitEvent.Action
        if rule.force {
            _ = killService.forceQuit(pid: proc.pid)
            action = .force
        } else {
            _ = killService.gracefulQuit(pid: proc.pid)
            action = .graceful
        }
        return .init(
            timestamp: now,
            processName: proc.name,
            pid: proc.pid,
            ruleName: rule.name,
            action: action
        )
    }

    /// OR's together whichever system-pressure thresholds are configured on the rule.
    /// A rule with no thresholds configured never fires.
    private func systemPressureConditionMet(rule: AutoQuitRule, snapshot: SystemSnapshot) -> Bool {
        if rule.sysFreeMemoryBelowPercent > 0 {
            let freePercent = 100 - snapshot.memoryUsedPercent
            if freePercent < rule.sysFreeMemoryBelowPercent { return true }
        }
        if rule.sysFreeMemoryBelowGB > 0 {
            let freeBytes = snapshot.memoryTotalBytes > snapshot.memoryUsedBytes
                ? snapshot.memoryTotalBytes - snapshot.memoryUsedBytes
                : 0
            let freeGB = Double(freeBytes) / 1_073_741_824
            if freeGB < rule.sysFreeMemoryBelowGB { return true }
        }
        if rule.sysCPUAbovePercent > 0 {
            if snapshot.cpuUsagePercent > rule.sysCPUAbovePercent { return true }
        }
        return false
    }

    func clearEvents() {
        recentEvents.removeAll()
    }

    // MARK: - Matching

    private func matches(rule: AutoQuitRule, proc: ProcessRow) -> Bool {
        guard targetMatches(rule: rule, proc: proc) else { return false }

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

    /// Case-insensitive substring match on process name/path — the "which processes does this
    /// rule target" check, shared by both trigger modes. Empty fields are ignored.
    private func targetMatches(rule: AutoQuitRule, proc: ProcessRow) -> Bool {
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
        return true
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
