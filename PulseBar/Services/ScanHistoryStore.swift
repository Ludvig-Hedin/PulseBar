import Foundation

/// Persistent store for completed scans. File-based JSON under Application
/// Support: a small `index.json` (always loaded — powers the history list,
/// trends, and repeat-offender rollup) plus one fat `<uuid>.json` per scan
/// (loaded lazily for the detail view).
@MainActor
final class ScanHistoryStore: ObservableObject {
    /// Newest-first. Lean entries only.
    @Published private(set) var index: [ScanSnapshotIndexEntry] = []

    private let directory: URL?
    private let indexURL: URL?

    // Retention.
    private let maxSnapshots = 100
    private let maxAgeDays: TimeInterval = 365

    private var cachedOffenders: [RepeatOffender]?

    init() {
        directory = ApplicationSupport.directory(subpath: "scans")
        indexURL = directory?.appendingPathComponent("index.json")
        loadIndex()
    }

    // MARK: - Recording

    /// Persists a completed scan: writes the fat file, inserts the index entry,
    /// prunes to the retention limits, and rewrites the index.
    func record(_ snapshot: ScanSnapshot) {
        guard let directory else { return }
        let fileURL = directory.appendingPathComponent(snapshot.fileNameSafe)
        if let data = try? JSONEncoder.iso.encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
        index.insert(snapshot.indexEntry, at: 0)
        enforceRetention()
        writeIndex()
        cachedOffenders = nil
    }

    /// Lazily loads the fat snapshot file for a detail view.
    func loadSnapshot(id: UUID) async -> ScanSnapshot? {
        guard let directory else { return nil }
        let fileURL = directory.appendingPathComponent("\(id.uuidString).json")
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            return try? JSONDecoder.iso.decode(ScanSnapshot.self, from: data)
        }.value
    }

    func delete(id: UUID) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id.uuidString).json"))
        index.removeAll { $0.id == id }
        writeIndex()
        cachedOffenders = nil
    }

    func clearAll() {
        guard let directory else { return }
        for entry in index {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.fileName))
        }
        index.removeAll()
        writeIndex()
        cachedOffenders = nil
    }

    // MARK: - Repeat offenders (cross-scan rollup)

    /// Folders that appear with junk across `minAppearances`+ scans, ranked by
    /// how often they recur then by latest size. Computed over the small index —
    /// no fat files loaded. Cached until the index changes.
    func repeatOffenders(minAppearances: Int = 2) -> [RepeatOffender] {
        if let cachedOffenders { return cachedOffenders.filter { $0.appearances >= minAppearances } }

        // Group every scan's top folders by key. Index is newest-first.
        var groups: [String: [(entry: ScanSnapshotIndexEntry, folder: FolderAggregate)]] = [:]
        for entry in index {
            for folder in entry.topFolders {
                groups[folder.folderKey, default: []].append((entry, folder))
            }
        }

        var offenders: [RepeatOffender] = []
        for (key, occurrences) in groups {
            // occurrences preserve index order (newest-first).
            guard let newest = occurrences.first, let oldest = occurrences.last else { continue }
            offenders.append(RepeatOffender(
                folderKey: key,
                displayPath: newest.folder.displayPath,
                appearances: occurrences.count,
                firstSizeBytes: oldest.folder.sizeBytes,
                latestSizeBytes: newest.folder.sizeBytes,
                lastSeenAt: newest.entry.finishedAt,
                dominantCategory: newest.folder.dominantCategory
            ))
        }
        offenders.sort {
            $0.appearances != $1.appearances
                ? $0.appearances > $1.appearances
                : $0.latestSizeBytes > $1.latestSizeBytes
        }
        cachedOffenders = offenders
        return offenders.filter { $0.appearances >= minAppearances }
    }

    // MARK: - Trends (built from the index)

    /// Junk-over-time, oldest → newest (chart-friendly order).
    var junkTrend: [TrendPoint] {
        index.reversed().map { TrendPoint(date: $0.finishedAt, bytes: $0.totalJunkBytes) }
    }

    var diskFreeTrend: [TrendPoint] {
        index.reversed().map { TrendPoint(date: $0.finishedAt, bytes: $0.freeBytes) }
    }

    /// Per-category totals over time for the top `n` categories (by latest size).
    func categoryTrend(top n: Int) -> [CategoryTrendPoint] {
        guard let latest = index.first else { return [] }
        let topCategories = latest.categoryTotals
            .sorted { $0.totalSizeBytes > $1.totalSizeBytes }
            .prefix(n)
            .map(\.category)
        let topSet = Set(topCategories)

        var points: [CategoryTrendPoint] = []
        for entry in index.reversed() {
            for summary in entry.categoryTotals where topSet.contains(summary.category) {
                points.append(CategoryTrendPoint(date: entry.finishedAt,
                                                 category: summary.category,
                                                 bytes: summary.totalSizeBytes))
            }
        }
        return points
    }

    // MARK: - Persistence internals

    private func loadIndex() {
        guard let indexURL, let data = try? Data(contentsOf: indexURL) else { return }
        if let decoded = try? JSONDecoder.iso.decode([ScanSnapshotIndexEntry].self, from: data) {
            index = decoded.sorted { $0.finishedAt > $1.finishedAt }
        }
    }

    private func writeIndex() {
        guard let indexURL, let data = try? JSONEncoder.iso.encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func enforceRetention() {
        let cutoff = Date().addingTimeInterval(-maxAgeDays * 86_400)
        var kept: [ScanSnapshotIndexEntry] = []
        var dropped: [ScanSnapshotIndexEntry] = []
        for (offset, entry) in index.sorted(by: { $0.finishedAt > $1.finishedAt }).enumerated() {
            if offset < maxSnapshots && entry.finishedAt >= cutoff {
                kept.append(entry)
            } else {
                dropped.append(entry)
            }
        }
        if let directory {
            for entry in dropped {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.fileName))
            }
        }
        index = kept
    }
}

private extension ScanSnapshot {
    var fileNameSafe: String { "\(id.uuidString).json" }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Snapshot construction

/// Builds a `ScanSnapshot` from a completed scan's live results: maps items to
/// DTOs, aggregates junk by owning folder, and caps everything so the on-disk
/// file stays small.
enum SnapshotBuilder {
    static func build(id: UUID,
                      tier: ScanTier,
                      startedAt: Date,
                      finishedAt: Date,
                      results: [CategoryResult],
                      disk: DiskUsage?,
                      topItemLimit: Int = 200,
                      folderLimit: Int = 50) -> ScanSnapshot {
        let cleanable = results.filter { $0.category.isNormallyCleanable }

        let categories = results.map {
            CategorySummary(category: $0.category,
                            totalSizeBytes: $0.totalSizeBytes,
                            itemCount: $0.itemCount,
                            truncated: $0.truncated)
        }

        // Reclaimable junk headline mirrors StorageState.totalJunkBytes semantics.
        let junkBytes = results
            .filter { $0.category != .purgeableSpace && $0.category != .docker && $0.category != .largeFiles }
            .reduce(UInt64(0)) { $0 + $1.totalSizeBytes }

        // Top items across cleanable categories, size-sorted.
        let allItems = cleanable.flatMap(\.items)
        let topItems = allItems
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .prefix(topItemLimit)
            .map { PersistedItem(path: $0.url.path, sizeBytes: $0.sizeBytes,
                                 modifiedAt: $0.modifiedAt, isDirectory: $0.isDirectory,
                                 category: $0.category) }

        let folders = aggregateFolders(items: allItems, limit: folderLimit)

        let errors = results.flatMap { result in
            result.errors.prefix(20).map { PersistedScanError(path: $0.path, reason: $0.displayMessage) }
        }

        return ScanSnapshot(
            id: id,
            tier: tier,
            startedAt: startedAt,
            finishedAt: finishedAt,
            diskTotalBytes: disk?.totalBytes ?? 0,
            diskFreeBytes: disk?.freeBytes ?? 0,
            diskPurgeableBytes: disk?.purgeableBytes ?? 0,
            totalJunkBytes: junkBytes,
            categories: categories,
            folders: folders,
            topItems: Array(topItems),
            errors: Array(errors.prefix(50))
        )
    }

    private static func aggregateFolders(items: [CleanableItem], limit: Int) -> [FolderAggregate] {
        struct Accumulator {
            var displayPath: String
            var bytes: UInt64 = 0
            var count: Int = 0
            var categoryBytes: [StorageCategory: UInt64] = [:]
        }
        var groups: [String: Accumulator] = [:]
        for item in items {
            let (key, display) = FolderKey.normalize(item.url)
            var acc = groups[key] ?? Accumulator(displayPath: display)
            acc.bytes &+= item.sizeBytes
            acc.count += 1
            acc.categoryBytes[item.category, default: 0] &+= item.sizeBytes
            groups[key] = acc
        }
        return groups
            .map { key, acc in
                let dominant = acc.categoryBytes.max { $0.value < $1.value }?.key ?? .userCache
                return FolderAggregate(folderKey: key, displayPath: acc.displayPath,
                                       sizeBytes: acc.bytes, itemCount: acc.count,
                                       dominantCategory: dominant)
            }
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .prefix(limit)
            .map { $0 }
    }
}

/// Normalizes a cleanable item's path to its owning project/cache root so junk
/// churn rolls up per project (not per nested dir) across scans.
enum FolderKey {
    private static let collapseMarkers: Set<String> = [
        "node_modules", ".next", ".nuxt", "dist", "build", "target", "venv", ".venv",
        "DerivedData", ".gradle", "__pycache__", ".cache", "Pods", ".turbo",
    ]

    /// Returns (case-folded key, `~`-abbreviated display) for the owning folder.
    static func normalize(_ url: URL) -> (key: String, display: String) {
        let standardized = url.resolvingSymlinksInPath().standardizedFileURL
        let components = standardized.pathComponents

        // Cut the path just before the first marker component (its parent = the
        // project/owner). Otherwise fall back to the item's parent directory.
        var ownerComponents = Array(standardized.deletingLastPathComponent().pathComponents)
        if let markerIndex = components.firstIndex(where: { collapseMarkers.contains($0) }), markerIndex > 0 {
            ownerComponents = Array(components.prefix(markerIndex))
        }

        let ownerPath = ownerComponents.isEmpty
            ? "/"
            : ownerComponents.joined(separator: "/").replacingOccurrences(of: "//", with: "/")
        let normalizedPath = ownerPath.hasPrefix("/") ? ownerPath : "/" + ownerPath

        return (key: normalizedPath.lowercased(), display: abbreviate(normalizedPath))
    }

    private static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
