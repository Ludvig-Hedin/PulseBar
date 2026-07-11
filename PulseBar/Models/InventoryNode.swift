import Foundation

/// A folder in the whole-disk inventory (Ultra Scan). Aggregated at the folder
/// level — never per file — so a full-volume map stays bounded in memory:
/// a node keeps only its top children by size, folding the rest into a synthetic
/// "(smaller items)" bucket.
///
/// Inventory nodes are a read-only visualisation type. They have no path into
/// `CleanupService`; the Ultra map only reveals files in Finder.
struct InventoryNode: Identifiable, Hashable {
    let url: URL
    /// Recursive allocated size of everything under this folder.
    let totalBytes: UInt64
    /// Recursive count of regular files.
    let fileCount: Int
    /// Newest modification date anywhere in the subtree (old = abandoned).
    let modifiedAt: Date
    /// True for the synthetic "(smaller items)" roll-up child.
    let isAggregate: Bool
    /// Largest children, capped. Empty for leaves and aggregate buckets.
    let topChildren: [InventoryNode]

    var id: URL { url }

    var displayName: String {
        if isAggregate { return "Smaller items" }
        if url.path == "/" { return "Macintosh HD" }
        return url.lastPathComponent
    }

    /// Only real folders with children can be drilled into.
    var isNavigable: Bool { !isAggregate && !topChildren.isEmpty }
}

/// Live progress for an in-flight inventory walk.
struct InventoryProgress: Equatable {
    var scannedFiles: Int
    var scannedBytes: UInt64
    var startedAt: Date
}

/// Resource envelope for the whole-disk inventory walk. Bounds memory (retain
/// only sizeable nodes, top-N children) and wall-clock time.
struct InventoryBudget: Equatable {
    var overallDeadlineSeconds: TimeInterval
    /// Folders smaller than this aren't retained as individual nodes — they're
    /// summed into their parent's "(smaller items)" bucket.
    var minReportBytes: UInt64
    /// Max individually-retained children per folder (largest kept).
    var maxChildrenPerNode: Int
    /// Beyond this depth, subtrees are summed but not retained as nodes.
    var maxDepth: Int
    /// Global backstop on the number of retained nodes.
    var maxTotalNodes: Int

    static let `default` = InventoryBudget(
        overallDeadlineSeconds: 600,
        minReportBytes: 50 * 1_024 * 1_024, // 50 MB
        maxChildrenPerNode: 14,
        maxDepth: 16,
        maxTotalNodes: 20_000
    )
}
