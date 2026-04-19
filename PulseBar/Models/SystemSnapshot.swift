import Foundation

struct SystemSnapshot: Equatable {
    var timestamp: Date = .now

    var cpuUsagePercent: Double = 0
    var memoryUsedBytes: UInt64 = 0
    var memoryTotalBytes: UInt64 = 0
    var memoryPressure: MemoryPressure = .normal

    var batteryPercent: Double? = nil
    var batteryIsCharging: Bool = false
    var batteryMinutesRemaining: Int? = nil

    var networkDownloadBytesPerSecond: UInt64 = 0
    var networkUploadBytesPerSecond: UInt64 = 0

    var runningProcessCount: Int = 0
    var devServerCount: Int = 0

    /// Memory used as a ratio of total (0..1). Convenience for UI bars.
    var memoryUsedRatio: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return min(1, Double(memoryUsedBytes) / Double(memoryTotalBytes))
    }

    /// Memory usage expressed as a percent (0..100).
    var memoryUsedPercent: Double { memoryUsedRatio * 100 }

    enum MemoryPressure: String {
        case normal
        case warning
        case critical
    }
}
