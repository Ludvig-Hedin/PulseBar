import Foundation
import AppKit

final class ProcessService {
    private let detector = DevServerDetector()

    func runningProcesses(portMap: [Int32: [Int]]) -> [ProcessRow] {
        let apps = NSWorkspace.shared.runningApplications

        return apps.map { app in
            let pid = app.processIdentifier
            let cpu = ProcessSampling.cpuPercent(pid: pid) ?? 0
            let memory = ProcessSampling.memoryBytes(pid: pid) ?? 0
            let ports = portMap[pid] ?? []
            let devInfo = detector.detect(appName: app.localizedName ?? "", executablePath: app.executableURL?.path, ports: ports)

            let kind: ProcessRow.Kind = {
                if app.activationPolicy == .regular { return .app }
                if app.bundleIdentifier == nil { return .cli }
                if app.activationPolicy == .accessory || app.activationPolicy == .prohibited { return .background }
                return .unknown
            }()

            return ProcessRow(
                id: pid,
                pid: pid,
                name: app.localizedName ?? "Unknown",
                bundleIdentifier: app.bundleIdentifier,
                executablePath: app.executableURL?.path,
                launchDate: app.launchDate,
                cpuPercent: cpu,
                memoryBytes: memory,
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
