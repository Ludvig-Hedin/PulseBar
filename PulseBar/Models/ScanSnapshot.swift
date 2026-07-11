import Foundation

/// Persisted record of a completed scan. Two tiers:
/// - `ScanSnapshotIndexEntry` is the lean, always-loaded summary (kept in
///   `index.json`) that powers the history list, trend charts, and
///   repeat-offender rollup without touching a fat file.
/// - `ScanSnapshot` is the fat per-scan file (`<uuid>.json`), loaded only when a
///   scan's detail view is opened.
///
/// We persist DTOs (`PersistedItem`, etc.) rather than the live scan models so
/// the on-disk format is stable and bounded.

// MARK: - Compact summaries (index)

struct CategorySummary: Codable, Hashable, Identifiable {
    let category: StorageCategory
    let totalSizeBytes: UInt64
    let itemCount: Int
    let truncated: Bool
    var id: StorageCategory { category }
}

/// A folder that accumulated junk in one scan, keyed by a normalized owning path.
struct FolderAggregate: Codable, Hashable, Identifiable {
    let folderKey: String        // normalized project/owner path (case-folded)
    let displayPath: String      // `~`-abbreviated for display
    let sizeBytes: UInt64
    let itemCount: Int
    let dominantCategory: StorageCategory
    var id: String { folderKey }
}

/// Lean entry kept in `index.json`. Everything the history list, trends, and
/// repeat-offender rollup need lives here.
struct ScanSnapshotIndexEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let tier: ScanTier
    let startedAt: Date
    let finishedAt: Date
    let totalBytes: UInt64          // disk capacity at scan time
    let freeBytes: UInt64
    let purgeableBytes: UInt64
    let totalJunkBytes: UInt64      // reclaimable junk headline
    let itemCountTotal: Int
    let categoryTotals: [CategorySummary]
    let topFolders: [FolderAggregate]

    var durationSeconds: Double { finishedAt.timeIntervalSince(startedAt) }
    var fileName: String { "\(id.uuidString).json" }
}

// MARK: - Fat snapshot (per-file)

struct PersistedItem: Codable, Hashable, Identifiable {
    let path: String
    let sizeBytes: UInt64
    let modifiedAt: Date
    let isDirectory: Bool
    let category: StorageCategory
    var id: String { path }
    var displayName: String { (path as NSString).lastPathComponent }
}

struct PersistedScanError: Codable, Hashable {
    let path: String
    let reason: String
}

struct ScanSnapshot: Identifiable, Codable {
    let id: UUID
    let tier: ScanTier
    let startedAt: Date
    let finishedAt: Date
    let diskTotalBytes: UInt64
    let diskFreeBytes: UInt64
    let diskPurgeableBytes: UInt64
    let totalJunkBytes: UInt64
    let categories: [CategorySummary]
    let folders: [FolderAggregate]
    let topItems: [PersistedItem]
    let errors: [PersistedScanError]

    /// Projects the fat snapshot down to its lean index entry.
    var indexEntry: ScanSnapshotIndexEntry {
        ScanSnapshotIndexEntry(
            id: id,
            tier: tier,
            startedAt: startedAt,
            finishedAt: finishedAt,
            totalBytes: diskTotalBytes,
            freeBytes: diskFreeBytes,
            purgeableBytes: diskPurgeableBytes,
            totalJunkBytes: totalJunkBytes,
            itemCountTotal: categories.reduce(0) { $0 + $1.itemCount },
            categoryTotals: categories,
            topFolders: Array(folders.prefix(20))
        )
    }
}

// MARK: - Cross-scan rollup

/// A folder that keeps showing up with junk across multiple scans.
struct RepeatOffender: Identifiable, Hashable {
    let folderKey: String
    let displayPath: String
    let appearances: Int
    let firstSizeBytes: UInt64
    let latestSizeBytes: UInt64
    let lastSeenAt: Date
    let dominantCategory: StorageCategory
    var id: String { folderKey }

    var growthBytes: Int64 { Int64(bitPattern: latestSizeBytes) - Int64(bitPattern: firstSizeBytes) }
}

// MARK: - Trend series

struct TrendPoint: Identifiable, Hashable {
    let date: Date
    let bytes: UInt64
    var id: Date { date }
}

struct CategoryTrendPoint: Identifiable, Hashable {
    let date: Date
    let category: StorageCategory
    let bytes: UInt64
    var id: String { "\(category.rawValue)-\(date.timeIntervalSince1970)" }
}
