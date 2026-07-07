import Foundation
import AppKit

final class ProcessService: @unchecked Sendable {
    private let detector = DevServerDetector()

    func runningProcesses(portMap: [Int32: [Int]]) -> [ProcessRow] {
        let apps = NSWorkspace.shared.runningApplications
        let processTree = ProcessTree(identities: ProcessSampling.allProcessIdentities())
        var cpuCache: [Int32: Double] = [:]
        var memoryCache: [Int32: UInt64] = [:]

        func cpuPercent(for pid: Int32) -> Double {
            if let cached = cpuCache[pid] { return cached }
            let value = ProcessSampling.cpuPercent(pid: pid) ?? 0
            cpuCache[pid] = value
            return value
        }

        func memoryBytes(for pid: Int32) -> UInt64 {
            if let cached = memoryCache[pid] { return cached }
            let value = ProcessSampling.memoryBytes(pid: pid) ?? 0
            memoryCache[pid] = value
            return value
        }

        return apps.map { app in
            let pid = app.processIdentifier
            let kind: ProcessRow.Kind = {
                if app.activationPolicy == .regular { return .app }
                if app.bundleIdentifier == nil { return .cli }
                if app.activationPolicy == .accessory || app.activationPolicy == .prohibited { return .background }
                return .unknown
            }()

            let sampledPIDs = kind == .app
                ? processTree.recursivePIDs(rootedAt: pid)
                : [pid]
            let cpu = sampledPIDs.reduce(0) { total, childPID in
                total + cpuPercent(for: childPID)
            }
            let memory = sampledPIDs.reduce(UInt64(0)) { total, childPID in
                total + memoryBytes(for: childPID)
            }
            let ports = sampledPIDs
                .flatMap { portMap[$0] ?? [] }
                .uniquedSorted()
            let devInfo = detector.detect(appName: app.localizedName ?? "", executablePath: app.executableURL?.path, ports: ports)

            return ProcessRow(
                id: pid,
                pid: pid,
                name: app.localizedName ?? "Unknown",
                bundleIdentifier: app.bundleIdentifier,
                executablePath: app.executableURL?.path,
                launchDate: app.launchDate,
                cpuPercent: cpu,
                memoryBytes: memory,
                sampledPIDs: sampledPIDs,
                kind: kind,
                isFrontmost: app.isActive,
                isTerminated: app.isTerminated,
                ports: ports,
                isLikelyDevServer: devInfo.isDevServer,
                devServerKind: devInfo.kind
            )
        }
        .sorted { lhs, rhs in
            if lhs.isLikelyDevServer != rhs.isLikelyDevServer {
                return lhs.isLikelyDevServer && !rhs.isLikelyDevServer
            }
            return lhs.cpuPercent > rhs.cpuPercent
        }
    }
}

private struct ProcessTree {
    private let childrenByParent: [Int32: [Int32]]

    init(identities: [ProcessSampling.ProcessIdentity]) {
        childrenByParent = Dictionary(grouping: identities, by: \.parentPID)
            .mapValues { identities in identities.map(\.pid) }
    }

    func recursivePIDs(rootedAt root: Int32) -> [Int32] {
        var result: [Int32] = []
        var visited = Set<Int32>()
        var stack = [root]

        while let pid = stack.popLast() {
            guard visited.insert(pid).inserted else { continue }
            result.append(pid)
            stack.append(contentsOf: childrenByParent[pid] ?? [])
        }

        return result
    }
}

private extension Array where Element == Int {
    func uniquedSorted() -> [Int] {
        Array(Set(self)).sorted()
    }
}
