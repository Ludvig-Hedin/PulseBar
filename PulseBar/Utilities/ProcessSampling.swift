// Uses proc_pidinfo (libproc) instead of task_for_pid.
// task_for_pid requires com.apple.security.get-task-allow (debug-only entitlement)
// and fails for all other processes without it — which is why every process showed 0.
// proc_pidinfo works for same-user processes without any entitlements.

import Foundation
import Darwin

// Stable kernel ABI — defined in <sys/proc_info.h>
private let PROC_PIDTASKINFO_FLAVOR: Int32 = 4

enum ProcessSampling {
    struct ProcessIdentity: Hashable {
        let pid: Int32
        let parentPID: Int32
    }

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

    /// Drop cached CPU samples for PIDs that are no longer running. Without this the
    /// sample dict grows unbounded over long-lived sessions as short-lived processes exit.
    static func prune(activePIDs: Set<Int32>) {
        samplesLock.lock()
        cpuSamples = cpuSamples.filter { activePIDs.contains($0.key) }
        samplesLock.unlock()
    }

    /// Returns memory in bytes for `pid`.
    /// Uses physical footprint first because it tracks Activity Monitor's Memory column
    /// more closely than raw resident size. Falls back to resident size when footprint
    /// is unavailable for a process.
    /// Returns nil if the process is inaccessible.
    static func memoryBytes(pid: Int32) -> UInt64? {
        if let footprint = physicalFootprintBytes(pid: pid), footprint > 0 {
            return footprint
        }

        var ti = proc_taskinfo()
        let ret = proc_pidinfo(pid, PROC_PIDTASKINFO_FLAVOR, 0, &ti,
                               Int32(MemoryLayout<proc_taskinfo>.size))
        guard ret > 0 else { return nil }
        return ti.pti_resident_size
    }

    /// Snapshot PID/parent PID relationships for the whole system. This lets callers
    /// aggregate helper and renderer processes under a regular app without parsing `ps`.
    static func allProcessIdentities() -> [ProcessIdentity] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length = 0

        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0 else {
            return []
        }

        let stride = MemoryLayout<kinfo_proc>.stride
        var attempts = 0

        while attempts < 3 {
            let requestedCount = max(length / stride, 1)
            var processes = [kinfo_proc](repeating: kinfo_proc(), count: requestedCount)
            let status = processes.withUnsafeMutableBufferPointer { buffer in
                sysctl(&mib, u_int(mib.count), buffer.baseAddress, &length, nil, 0)
            }

            if status == 0 {
                let actualCount = min(length / stride, processes.count)
                return processes.prefix(actualCount).compactMap { process in
                    let pid = process.kp_proc.p_pid
                    guard pid > 0 else { return nil }
                    return ProcessIdentity(pid: pid, parentPID: process.kp_eproc.e_ppid)
                }
            }

            guard errno == ENOMEM else { return [] }
            attempts += 1
            length += stride * 64
        }

        return []
    }

    private static func physicalFootprintBytes(pid: Int32) -> UInt64? {
        var usage = rusage_info_current()
        let capacity = max(
            1,
            MemoryLayout<rusage_info_current>.stride / MemoryLayout<rusage_info_t?>.stride
        )
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: capacity) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
            }
        }

        guard result == 0 else { return nil }
        return usage.ri_phys_footprint
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

    /// Hard upper bound on how long any single shell invocation may run.
    /// `lsof` can stall on a stuck NFS mount or unresponsive filesystem; without this
    /// watchdog the calling background thread would be pinned indefinitely and the
    /// process tab's port info would silently stop updating.
    private static let shellTimeout: TimeInterval = 5.0

    private static func runShell(_ command: String) -> String? {
        let task = Process()
        let pipe = Pipe()
        // /bin/sh -c avoids loading login shell configs (.zprofile, NVM, conda, etc.)
        // which can add 1-5s per invocation and blow the 5s watchdog on dev machines.
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", command]
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return nil
        }

        // Watchdog: terminate the task if it overruns the timeout. We use a DispatchWorkItem
        // so we can cancel it cleanly when the task exits in time.
        let watchdog = DispatchWorkItem { [weak task] in
            guard let task, task.isRunning else { return }
            task.terminate()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + shellTimeout, execute: watchdog)

        task.waitUntilExit()
        watchdog.cancel()

        // If the watchdog fired, exit status is non-zero — treat as no result.
        guard task.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        Array(Set(self))
    }
}
