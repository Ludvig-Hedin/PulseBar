import Foundation

/// Compact, `Codable` mirror of live app state sized for the App Group bridge.
/// The widget extension is sandboxed and cannot compute this itself — the main
/// app assembles and writes it every refresh tick via `WidgetSnapshotStore`.
struct WidgetSnapshot: Codable, Equatable {
    var generatedAt: Date

    var cpuPercent: Double
    /// Last ~20 samples, 0...100. Tail of `PulseBarViewModel.cpuHistory`.
    var cpuHistory: [Double]

    var ramUsedBytes: UInt64
    var ramTotalBytes: UInt64
    var ramPressure: String
    var ramHistory: [Double]

    var netDownBytesPerSecond: UInt64
    var netUpBytesPerSecond: UInt64

    var diskUsedBytes: UInt64?
    var diskTotalBytes: UInt64?
    var diskFreeBytes: UInt64?

    var batteryPercent: Double?
    var batteryIsCharging: Bool?

    var devServers: [WidgetDevServer]
    var topProcesses: [WidgetProcess]
    var runningProcessCount: Int

    var ramUsedRatio: Double {
        guard ramTotalBytes > 0 else { return 0 }
        return min(1, Double(ramUsedBytes) / Double(ramTotalBytes))
    }
    var ramUsedPercent: Double { ramUsedRatio * 100 }

    var diskUsedRatio: Double {
        guard let used = diskUsedBytes, let total = diskTotalBytes, total > 0 else { return 0 }
        return min(1, Double(used) / Double(total))
    }
    var diskUsedPercent: Double { diskUsedRatio * 100 }

    static let placeholder = WidgetSnapshot(
        generatedAt: .now,
        cpuPercent: 34,
        cpuHistory: (0..<20).map { _ in Double.random(in: 15...55) },
        ramUsedBytes: 9_800_000_000,
        ramTotalBytes: 16_000_000_000,
        ramPressure: "normal",
        ramHistory: (0..<20).map { _ in Double.random(in: 40...70) },
        netDownBytesPerSecond: 2_400_000,
        netUpBytesPerSecond: 320_000,
        diskUsedBytes: 412_000_000_000,
        diskTotalBytes: 994_000_000_000,
        diskFreeBytes: 582_000_000_000,
        batteryPercent: 78,
        batteryIsCharging: false,
        devServers: [
            WidgetDevServer(name: "next dev", port: 3000, kind: "Node"),
            WidgetDevServer(name: "vite", port: 5173, kind: "Vite")
        ],
        topProcesses: [
            WidgetProcess(pid: 1, name: "Xcode", cpuPercent: 42, memoryBytes: 2_100_000_000, kind: "App"),
            WidgetProcess(pid: 2, name: "node", cpuPercent: 18, memoryBytes: 340_000_000, kind: "CLI"),
            WidgetProcess(pid: 3, name: "Safari", cpuPercent: 9, memoryBytes: 890_000_000, kind: "App")
        ],
        runningProcessCount: 214
    )
}

struct WidgetDevServer: Codable, Equatable, Identifiable {
    var id: String { "\(port)-\(name)" }
    let name: String
    let port: Int
    let kind: String?
}

struct WidgetProcess: Codable, Equatable, Identifiable {
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    let cpuPercent: Double
    let memoryBytes: UInt64
    let kind: String
}
