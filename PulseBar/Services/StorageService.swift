import Foundation
import Combine

/// Front door for everything Storage-tab related. Owns the actor-isolated
/// scan engine, the FDA detector, and the published `StorageState` the UI binds to.
@MainActor
final class StorageService: ObservableObject {
    @Published private(set) var state = StorageState()

    private let purgeableSpaceProbe = PurgeableSpaceProbe()
    private let scanEngine = ScanEngine()
    private let cleanupService = CleanupService()
    private let fdaDetector = FullDiskAccessDetector()

    /// Currently-running scan consumer task. Cancelled when a new scan is started
    /// or when the user explicitly cancels.
    private var scanConsumer: Task<Void, Never>?

    /// Categories included in the most recently started scan. Used to populate
    /// `scanProgress.targetCategories`.
    private var currentScanCategories: [StorageCategory] = []

    init() {
        // Best-effort first FDA probe so the banner state is right on first open.
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.fdaDetector.hasFullDiskAccess()
            await MainActor.run { self.state.fullDiskAccessGranted = granted }
        }
    }

    // MARK: - Disk usage

    /// Refreshes disk-usage snapshot from the cheap probe. Safe to call every tick.
    func refreshDiskUsage() {
        if let usage = purgeableSpaceProbe.read() {
            state.diskUsage = usage
        }
    }

    // MARK: - Scans

    /// Starts a scan. Cancels any prior scan first. Updates `state.scanProgress` live.
    func startScan(_ categories: [StorageCategory]) {
        cancelScan()
        let target = expandSmartScan(categories)
        currentScanCategories = target
        state.scanProgress = ScanProgress(
            targetCategories: target,
            currentCategory: nil,
            startedAt: .now
        )
        state.lastScanError = nil

        scanConsumer = Task { [weak self] in
            guard let self else { return }
            let stream = await self.scanEngine.startScan(target)
            for await event in stream {
                if Task.isCancelled { break }
                await self.handle(event)
            }
            await MainActor.run {
                self.state.scanProgress = nil
            }
        }
    }

    func cancelScan() {
        scanConsumer?.cancel()
        scanConsumer = nil
        Task { await scanEngine.cancel() }
        state.scanProgress = nil
    }

    /// Replaces cached results from the scan engine on first Storage-tab open.
    func loadCachedResults() async {
        let cached = await scanEngine.currentResults()
        state.categoryResults = cached
    }

    // MARK: - Full Disk Access

    func recheckFullDiskAccess() async {
        let granted = await fdaDetector.recheck()
        state.fullDiskAccessGranted = granted
    }

    nonisolated func openFullDiskAccessSettings() {
        FullDiskAccessDetector.openSystemSettings()
    }

    // MARK: - Cleanup

    /// Executes a cleanup. Returns the records so the UI can summarise the result.
    /// Successfully-deleted items are pruned from `state.categoryResults` so the
    /// list stays in sync without forcing a full rescan.
    func deleteSelected(items: [CleanableItem], mode: DeletionMode) async -> [DeletionRecord] {
        let records = await cleanupService.delete(items: items, mode: mode)
        appendRecords(records)
        pruneDeletedItems(records: records)
        return records
    }

    func emptyTrash() async -> [DeletionRecord] {
        let records = await cleanupService.emptyTrash()
        appendRecords(records)
        // Trash category will be rescanned by the caller; pruning isn't useful here.
        return records
    }

    func pruneDocker(estimatedBytes: UInt64) async -> [DeletionRecord] {
        let records = await cleanupService.pruneDocker(estimatedBytes: estimatedBytes)
        appendRecords(records)

        let refreshed = await Task.detached(priority: .utility) {
            CategoryScanner.scan(category: .docker,
                                 deadline: Date().addingTimeInterval(CategoryScanner.defaultDeadlineSeconds),
                                 cancellation: { false })
        }.value
        state.categoryResults[.docker] = refreshed
        return records
    }

    func clearDeletionHistory() {
        state.recentDeletions.removeAll()
    }

    // MARK: - Internals (cleanup)

    private func appendRecords(_ records: [DeletionRecord]) {
        state.recentDeletions.append(contentsOf: records)
        if state.recentDeletions.count > 100 {
            state.recentDeletions.removeFirst(state.recentDeletions.count - 100)
        }
    }

    /// Removes deleted items from cached category results and updates totals.
    private func pruneDeletedItems(records: [DeletionRecord]) {
        let deletedURLs = Set(records.compactMap { $0.result.isSuccess ? $0.url : nil })
        guard !deletedURLs.isEmpty else { return }
        for (category, result) in state.categoryResults {
            let remaining = result.items.filter { !deletedURLs.contains($0.url) }
            guard remaining.count != result.items.count else { continue }
            let total = remaining.reduce(UInt64(0)) { $0 + $1.sizeBytes }
            state.categoryResults[category] = CategoryResult(
                category: category,
                items: remaining,
                totalSizeBytes: total,
                scannedAt: result.scannedAt,
                truncated: result.truncated,
                errors: result.errors
            )
        }
    }

    // MARK: - Internals

    private func handle(_ event: ScanEngine.Event) async {
        switch event {
        case .started(let category):
            state.scanProgress?.currentCategory = category

        case .partial(let category, let bytes, let count):
            state.scanProgress?.runningTotals[category] = bytes
            state.scanProgress?.runningCounts[category] = count

        case .completed(let result):
            state.categoryResults[result.category] = result
            state.scanProgress?.completed.insert(result.category)
            state.scanProgress?.runningTotals[result.category] = result.totalSizeBytes
            state.scanProgress?.runningCounts[result.category] = result.itemCount

        case .failed(let category, let error):
            state.lastScanError = error
            state.scanProgress?.completed.insert(category)

        case .finished:
            state.scanProgress = nil
        }
    }

    private func expandSmartScan(_ categories: [StorageCategory]) -> [StorageCategory] {
        if categories.contains(.smartScan) {
            return ScanEngine.smartScanCategories
        }
        return categories
    }
}
