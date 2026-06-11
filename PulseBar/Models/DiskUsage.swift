import Foundation

/// Snapshot of disk usage for a single volume. Populated by `PurgeableSpaceProbe`.
struct DiskUsage: Equatable, Hashable {
    let volumeURL: URL
    let totalBytes: UInt64
    /// `volumeAvailableCapacityForImportantUsageKey` — the value macOS would surface in Finder.
    /// Treats purgeable content as "available" because the OS reclaims it on demand.
    let availableImportantBytes: UInt64
    /// `volumeAvailableCapacityForOpportunisticUsageKey` — capacity strictly free right now.
    /// Lower than `availableImportantBytes` by exactly the purgeable amount.
    let availableOpportunisticBytes: UInt64

    var purgeableBytes: UInt64 {
        availableImportantBytes &- min(availableImportantBytes, availableOpportunisticBytes)
    }

    var freeBytes: UInt64 { availableImportantBytes }
    var usedBytes: UInt64 { totalBytes &- min(totalBytes, freeBytes) }
    var usedRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
    var usedPercent: Double { usedRatio * 100 }

    var totalFormatted: String { ByteFormatting.gigabytes(totalBytes) }
    var freeFormatted: String { ByteFormatting.gigabytes(freeBytes) }
    var usedFormatted: String { ByteFormatting.gigabytes(usedBytes) }
    var purgeableFormatted: String { ByteFormatting.gigabytes(purgeableBytes) }
}
