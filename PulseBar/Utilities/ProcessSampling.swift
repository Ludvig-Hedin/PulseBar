// Uses proc_pidinfo (libproc) instead of task_for_pid.
// task_for_pid requires com.apple.security.get-task-allow (debug-only entitlement)
// and fails for all other processes without it — which is why every process showed 0.
// proc_pidinfo works for same-user processes without any entitlements.

import Foundation
import Darwin

// Stable kernel ABI — defined in <sys/proc_info.h>
private let PROC_PIDTASKINFO_FLAVOR: Int32 = 4

enum ProcessSampling {

    // MARK: - Mach timebase (cached — never changes at runtime)

    /// pti_total_user / pti_total_system from proc_taskinfo are in Mach absolute time
    /// ticks, NOT nanoseconds. On Apple Silicon numer=125, denom=3 → 1 tick ≈ 41.67 ns.
    /// Without this conversion the per-process CPU% is ~42× too small and rounds to 0.
    private static let timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    // MARK: - Delta CPU cache (thread-safe)

    private static let samplesLock = NSLock()
    /// Keyed by PID. Stores the last sampled cumulative Mach-tick count + wall-clock time.
    private static var cpuSamples: [Int32: (totalTicks: UInt64, date: Date)] = [:]

    // MARK: - Public API

    /// Returns current CPU usage % for `pid`, computed as a delta over elapsed time.
    /// Returns 0 on the first call for a given PID (need two samples to compute a rate).
    /// Returns nil if the process is inaccessible (e.g. root-owned system process).
    static func cpuPercent(pid: Int32) -> Double? {
        var ti = proc_taskinfo()
        let ret = proc_pidinfo(pid, PROC_PIDTASKINFO_FLAVOR, 0, &ti,
                               Int32(MemoryLayout<proc_taskinfo>.size))
        guard ret > 0 else { return nil }

        // These are cumulative Mach absolute time ticks since the process launched.
        let totalTicks = ti.pti_total_user + ti.pti_total_system
        let now = Date()

        samplesLock.lock()
        let prev = cpuSamples[pid]
        cpuSamples[pid] = (totalTicks: totalTicks, date: now)
        samplesLock.unlock()

        // First sample — store baseline, return 0. Next tick computes the real rate.
        guard let prev else { return 0 }

        let elapsed = now.timeIntervalSince(prev.date)
        guard elapsed >= 0.05 else { return 0 }

        // Guard against counter reset on PID reuse
        let deltaTicks = totalTicks >= prev.totalTicks ? totalTicks - prev.totalTicks : 0

        // Convert Mach ticks → nanoseconds → seconds
        let cpuNanos = Double(deltaTicks) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom)
        let cpuSeconds = cpuNanos / 1_000_000_000.0

        // Clamp to 100% × core count (matches Activity Monitor)
        let maxPercent = Double(ProcessInfo.processInfo.activeProcessorCount) * 100.0
        return min((cpuSeconds / elapsed) * 100.0, maxPercent)
    }

    /// Returns resident memory in bytes for `pid`.
    /// Returns nil if the process is inaccessible.
    static func memoryBytes(pid: Int32) -> UInt64? {
        var ti = proc_taskinfo()
        let ret = proc_pidinfo(pid, PROC_PIDTASKINFO_FLAVOR, 0, &ti,
                               Int32(MemoryLayout<proc_taskinfo>.size))
        guard ret > 0 else { return nil }
        return ti.pti_resident_size
    }

    // MARK: - Port scanning

    static func allListeningPorts() -> [Int32: [Int]] {
        let command = "lsof -nP -iTCP -sTCP:LISTEN | awk 'NR>1 {print $2, $9}'"
        guard let output = runShell(command) else { return [:] }

        var result: [Int32: [Int]] = [:]
        let lines = output.split(separator: "\n")

        for line in lines {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2,
                  let pid = Int32(parts[0]) else { continue }

            let address = parts[1]
            if let colonIndex = address.lastIndex(of: ":") {
                let portString = address[address.index(after: colonIndex)...]
                if let port = Int(portString) {
                    result[pid, default: []].append(port)
                }
            }
        }

        return result
    }

    static func listeningPorts(pid: Int32) -> [Int] {
        let command = "lsof -Pan -p \(pid) -iTCP -sTCP:LISTEN | awk 'NR>1 {split($9,a,\":\"); print a[length(a)]}'"
        guard let output = runShell(command) else { return [] }

        return output
            .split(separator: "\n")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .uniqued()
            .sorted()
    }

    // MARK: - Shell helper

    private static func runShell(_ command: String) -> String? {
        let task = Process()
        let pipe = Pipe()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-lc", command]
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return nil
        }

        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        Array(Set(self))
    }
}
