import Foundation

/// Aggregate state observed by the Storage tab UI. Held by `StorageService`.
struct StorageState: Equatable {
    var diskUsage: DiskUsage?
    var categoryResults: [StorageCategory: CategoryResult] = [:]
    var scanProgress: ScanProgress?
    var recentDeletions: [DeletionRecord] = []
    var lastScanError: ScanError?
    var fullDiskAccessGranted: Bool? = nil

    /// Whole-disk read-only inventory (Ultra Scan). Separate from `categoryResults`
    /// — it never feeds the deletion flow.
    var inventoryRoot: InventoryNode?
    var inventoryProgress: InventoryProgress?

    /// Sum of all freshly-scanned, *deletable* category sizes. Purgeable space is
    /// reclaimed by macOS, Docker requires `docker system prune`, and Large Files
    /// is reveal-only user data; excluding them keeps "Junk found" honest about
    /// what a Smart Scan + Clean will reclaim.
    var totalJunkBytes: UInt64 {
        categoryResults.values
            .filter {
                $0.isFresh
                    && $0.category != .purgeableSpace
                    && $0.category != .docker
                    && $0.category != .largeFiles
            }
            .reduce(0) { $0 + $1.totalSizeBytes }
    }

    var lastScanAt: Date? {
        categoryResults.values.map(\.scannedAt).max()
    }

    var hasFreshScan: Bool {
        categoryResults.values.contains { $0.isFresh }
    }
}

/// Live state of an in-flight scan. Drives the live results panel.
struct ScanProgress: Equatable {
    /// Categories targeted in this scan run.
    let targetCategories: [StorageCategory]
    /// Category currently being walked, if any.
    var currentCategory: StorageCategory?
    /// Per-category running total of bytes seen so far. Coalesced at ~10 Hz.
    var runningTotals: [StorageCategory: UInt64] = [:]
    /// Per-category item counts seen so far.
    var runningCounts: [StorageCategory: Int] = [:]
    /// Categories that have finished (success or failure).
    var completed: Set<StorageCategory> = []
    /// Wall-clock start.
    let startedAt: Date

    var aggregateBytes: UInt64 {
        runningTotals.values.reduce(0, +)
    }

    var aggregateItems: Int {
        runningCounts.values.reduce(0, +)
    }

    var fractionDone: Double {
        guard !targetCategories.isEmpty else { return 0 }
        return Double(completed.count) / Double(targetCategories.count)
    }
}
