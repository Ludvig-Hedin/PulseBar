import Foundation

/// Cheap synchronous read of total / available / opportunistic capacity for a volume.
/// Safe to call from any actor; the underlying resource-value lookup completes in microseconds.
struct PurgeableSpaceProbe {
    /// Reads disk usage for the boot volume ("/").
    func read(volumeURL: URL = URL(fileURLWithPath: "/", isDirectory: true)) -> DiskUsage? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey,
        ]
        do {
            let values = try volumeURL.resourceValues(forKeys: keys)
            guard let total = values.volumeTotalCapacity else { return nil }
            let important = values.volumeAvailableCapacityForImportantUsage ?? 0
            let opportunistic = values.volumeAvailableCapacityForOpportunisticUsage ?? 0
            return DiskUsage(
                volumeURL: volumeURL,
                totalBytes: UInt64(max(0, total)),
                availableImportantBytes: UInt64(max(0, important)),
                availableOpportunisticBytes: UInt64(max(0, opportunistic))
            )
        } catch {
            return nil
        }
    }
}
