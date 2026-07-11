import Foundation
import Combine
import AppKit

/// Storage-tab UI facade over `StorageService`. Owns selection + filtering state
/// that's irrelevant outside the Storage tab.
@MainActor
final class StorageViewModel: ObservableObject {
    enum Subview: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case files = "Files"
        case categories = "Categories"
        case diskMap = "Disk Map"
        case settings = "Settings"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .dashboard:  return "chart.pie"
            case .files:      return "list.bullet.rectangle"
            case .categories: return "tray.full"
            case .diskMap:    return "square.grid.3x3.topleft.filled"
            case .settings:   return "slider.horizontal.3"
            }
        }
    }

    enum SortColumn: String, CaseIterable, Identifiable {
        case size = "Size"
        case name = "Name"
        case modified = "Modified"
        var id: String { rawValue }
    }

    enum SortDirection { case ascending, descending }

    enum CategoryActionKind: Equatable {
        case cleanable
        case revealOnly
        case externalAction
        case informational
    }

    let service: StorageService

    /// Republished so views can observe `StorageViewModel` alone.
    @Published private(set) var diskUsage: DiskUsage?
    @Published private(set) var state = StorageState()

    // MARK: - UI selection state

    /// Categories is the actionable surface (Smart Scan card + category list).
    /// Dashboard is informational; defaulting there makes users hunt for the cleanup
    /// flow. First-time users land on the action, not on a hero gauge with empty stats.
    @Published var subview: Subview = .categories
    @Published var fileCategoryFilter: StorageCategory?
    @Published var searchText: String = ""
    @Published var sortColumn: SortColumn = .size
    @Published var sortDirection: SortDirection = .descending
    @Published var selectedItems: Set<URL> = []

    /// Drives the CleanConfirmationDialog sheet.
    @Published var showCleanConfirmation: Bool = false
    /// Snapshot of the most recent cleanup batch — used by a brief success toast (Phase 4).
    @Published var lastCleanupSummary: CleanupSummary?
    /// True while a cleanup is in flight. Drives the StickyCleanBar's spinner and
    /// gates a second cleanup invocation.
    @Published private(set) var isCleaning: Bool = false
    @Published var showDockerPruneConfirmation: Bool = false
    @Published private(set) var isPruningDocker: Bool = false

    struct CleanupSummary: Equatable {
        enum Kind: Equatable {
            case files
            case docker
        }

        let kind: Kind
        let succeeded: Int
        let failed: Int
        let refused: Int
        let totalBytes: UInt64
        let completedAt: Date

        var totalFormatted: String { ByteFormatting.memory(totalBytes) }
    }

    private var cancellables = Set<AnyCancellable>()

    init(service: StorageService) {
        self.service = service
        service.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] new in
                guard let self else { return }
                self.state = new
                self.diskUsage = new.diskUsage
            }
            .store(in: &cancellables)
    }

    func refreshDiskUsage() { service.refreshDiskUsage() }

    // MARK: - Scans

    func startSmartScan() {
        startScan(tier: .quick)
    }

    /// Starts a tiered scan (Quick / Deep). Ultra uses the read-only inventory
    /// path and is started via its own entry point.
    func startScan(tier: ScanTier) {
        guard !tier.usesInventoryPath else { return }
        clearSelection()
        // Quick maps to the existing Smart Scan expansion; Deep passes its
        // explicit category set (quick categories + Large Files + dev artifacts).
        let categories = tier == .quick ? [.smartScan] : tier.categories
        service.startScan(categories, tier: tier)
    }

    func startScan(_ categories: [StorageCategory]) {
        clearSelection()
        service.startScan(categories)
    }

    func cancelScan() { service.cancelScan() }

    var isScanRunning: Bool { state.scanProgress != nil }

    // MARK: - Ultra Scan (whole-disk inventory)

    /// Starts the read-only whole-disk map and switches to the Disk Map view.
    func startUltraScan() {
        guard !isScanRunning, !isAutoCleaning else { return }
        subview = .diskMap
        service.startInventory()
    }

    func cancelUltraScan() { service.cancelInventory() }

    var isInventoryRunning: Bool { state.inventoryProgress != nil }
    var inventoryProgress: InventoryProgress? { state.inventoryProgress }
    var inventoryRoot: InventoryNode? { state.inventoryRoot }

    /// Opens a folder in Finder (Reveal). Ultra map is read-only — this is the
    /// only action it offers.
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Auto-clean (trash-only, manual)

    /// True while a Quick Scan + Clean run is in flight (scan + trash).
    @Published private(set) var isAutoCleaning = false
    /// Drives the one-time consent sheet shown before the first auto-clean.
    @Published var showAutoCleanConsent = false
    /// Result of the most recent auto-clean run — the UI surfaces it as a banner
    /// (success, "nothing found", or the circuit-breaker "paused" warning).
    @Published var lastAutoCleanOutcome: AutoCleanCoordinator.Outcome?

    /// Entry point for the "Quick Scan + Clean" button. Shows the consent sheet
    /// the first time; runs directly once the user has opted in.
    func requestQuickClean() {
        guard !isAutoCleaning, !isScanRunning else { return }
        if PreferencesService.shared.autoCleanPolicy.enabled {
            runAutoCleanNow()
        } else {
            showAutoCleanConsent = true
        }
    }

    /// User accepted the consent dialog: enable the policy and run immediately.
    func confirmAutoCleanConsent() {
        showAutoCleanConsent = false
        var policy = PreferencesService.shared.autoCleanPolicy
        policy.enabled = true
        PreferencesService.shared.autoCleanPolicy = policy
        runAutoCleanNow()
    }

    func cancelAutoCleanConsent() {
        showAutoCleanConsent = false
    }

    private func runAutoCleanNow() {
        guard !isAutoCleaning else { return }
        isAutoCleaning = true
        clearSelection()
        Task {
            let outcome = await service.autoCleanCoordinator.run(policy: PreferencesService.shared.autoCleanPolicy)
            self.lastAutoCleanOutcome = outcome
            if outcome.result == .cleaned {
                self.lastCleanupSummary = CleanupSummary(
                    kind: .files,
                    succeeded: outcome.itemsTrashed,
                    failed: 0,
                    refused: 0,
                    totalBytes: outcome.bytesReclaimed,
                    completedAt: outcome.at
                )
            }
            self.isAutoCleaning = false
        }
    }

    func showFiles(category: StorageCategory? = nil) {
        fileCategoryFilter = category
        searchText = ""
        subview = .files
    }

    // MARK: - Junk summary (Overview callout)

    struct JunkSummary {
        let totalBytes: UInt64
        let lastScanAt: Date?
        let isFresh: Bool

        var totalFormatted: String { ByteFormatting.gigabytes(totalBytes) }
    }

    var junkSummary: JunkSummary {
        JunkSummary(
            totalBytes: state.totalJunkBytes,
            lastScanAt: state.lastScanAt,
            isFresh: state.hasFreshScan
        )
    }

    // MARK: - Selection

    func toggleSelection(_ url: URL) {
        if selectedItems.contains(url) {
            selectedItems.remove(url)
        } else {
            selectedItems.insert(url)
        }
    }

    func selectAll(in category: StorageCategory) {
        // Respect the active search filter so "Select All" matches what the user sees.
        // Non-cleanable categories cannot be selected for the normal file cleaner.
        guard Self.isCleanable(category) else { return }
        for item in filteredItems(for: category) {
            selectedItems.insert(item.url)
        }
    }

    func deselectAll(in category: StorageCategory) {
        for item in filteredItems(for: category) {
            selectedItems.remove(item.url)
        }
    }

    func clearSelection() { selectedItems.removeAll() }

    /// Select every visible cleanable item across all categories by default, or
    /// within a specific review filter when the Files view is scoped.
    func selectAllCleanable(category: StorageCategory? = nil, searchText: String = "") {
        for item in allItemsSorted(category: category, searchText: searchText) {
            if Self.isCleanable(item.category) {
                selectedItems.insert(item.url)
            }
        }
    }

    /// Pre-select all junk then navigate to the Files view for quick review.
    func quickSelectAllAndShowFiles() {
        selectAllCleanable()
        showFiles()
    }

    func selectAllVisibleReviewItems() {
        selectAllCleanable(category: fileCategoryFilter, searchText: searchText)
    }

    func deselectAllVisibleReviewItems() {
        for item in allItemsSorted(category: fileCategoryFilter,
                                   searchText: searchText,
                                   includeRevealOnly: true) {
            selectedItems.remove(item.url)
        }
    }

    /// All cleanable items across every non-reveal-only category, sorted according
    /// to the current `sortColumn` / `sortDirection`. Optionally filtered by text.
    func allItemsSorted(category: StorageCategory? = nil,
                        searchText: String = "",
                        includeRevealOnly: Bool = false) -> [CleanableItem] {
        var items: [CleanableItem] = []
        if let category {
            if let result = state.categoryResults[category],
               Self.isCleanable(category) || includeRevealOnly {
                items.append(contentsOf: result.items)
            }
        } else {
            for result in state.categoryResults.values {
                guard Self.isCleanable(result.category) else { continue }
                items.append(contentsOf: result.items)
            }
        }
        let filtered: [CleanableItem]
        if searchText.isEmpty {
            filtered = items
        } else {
            filtered = items.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText)
                    || $0.parentDirectory.localizedCaseInsensitiveContains(searchText)
                    || $0.category.title.localizedCaseInsensitiveContains(searchText)
            }
        }
        let sorted: [CleanableItem]
        switch sortColumn {
        case .size:
            sorted = filtered.sorted { $0.sizeBytes < $1.sizeBytes }
        case .name:
            sorted = filtered.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .modified:
            sorted = filtered.sorted { $0.modifiedAt < $1.modifiedAt }
        }
        return sortDirection == .descending ? sorted.reversed() : sorted
    }

    /// Items the user has selected across all categories. Used by the Clean flow.
    /// Reveal-only categories (Large Files, Purgeable, Docker synthetic) are
    /// excluded as a safety belt: the UI hides their selection control too,
    /// but this filter is the authoritative gate.
    var selectedCleanables: [CleanableItem] {
        var out: [CleanableItem] = []
        for result in state.categoryResults.values {
            for item in result.items where selectedItems.contains(item.url) {
                if !Self.isCleanable(item.category) { continue }
                out.append(item)
            }
        }
        return out
    }

    static func actionKind(for category: StorageCategory) -> CategoryActionKind {
        switch category {
        case .largeFiles:     return .revealOnly
        case .docker:         return .externalAction
        case .purgeableSpace: return .informational
        default:              return .cleanable
        }
    }

    /// True when the regular file cleaner may select and remove files in a category.
    static func isCleanable(_ category: StorageCategory) -> Bool {
        actionKind(for: category) == .cleanable
    }

    var selectedTotalBytes: UInt64 {
        selectedCleanables.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedTotalCount: Int { selectedCleanables.count }

    /// Filtered + sorted items for the currently-selected category, used by
    /// `CategoryDetailView`.
    func filteredItems(for category: StorageCategory) -> [CleanableItem] {
        guard let result = state.categoryResults[category] else { return [] }
        let filtered: [CleanableItem]
        if searchText.isEmpty {
            filtered = result.items
        } else {
            filtered = result.items.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText)
                    || $0.parentDirectory.localizedCaseInsensitiveContains(searchText)
            }
        }
        let sorted: [CleanableItem]
        switch sortColumn {
        case .size:
            sorted = filtered.sorted { $0.sizeBytes < $1.sizeBytes }
        case .name:
            sorted = filtered.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .modified:
            sorted = filtered.sorted { $0.modifiedAt < $1.modifiedAt }
        }
        return sortDirection == .ascending ? sorted : sorted.reversed()
    }

    // MARK: - Cleanup

    func requestCleanup() {
        guard !selectedCleanables.isEmpty else { return }
        showCleanConfirmation = true
    }

    func performCleanup(mode: DeletionMode) {
        let items = selectedCleanables
        showCleanConfirmation = false
        guard !items.isEmpty, !isCleaning else { return }
        isCleaning = true
        Task {
            let records = await service.deleteSelected(items: items, mode: mode)
            // VM is @MainActor; Task inherits actor isolation, so direct assignment is fine.
            let succeeded = records.filter { if case .succeeded = $0.result { return true } else { return false } }
            let failed = records.filter { if case .failed = $0.result { return true } else { return false } }
            let refused = records.filter { if case .refused = $0.result { return true } else { return false } }
            let bytes = succeeded.reduce(UInt64(0)) { $0 + $1.sizeBytes }
            self.lastCleanupSummary = CleanupSummary(
                kind: .files,
                succeeded: succeeded.count,
                failed: failed.count,
                refused: refused.count,
                totalBytes: bytes,
                completedAt: .now
            )
            self.selectedItems = self.selectedItems.subtracting(succeeded.map(\.url))
            self.isCleaning = false
        }
    }

    func cancelCleanupConfirmation() {
        showCleanConfirmation = false
    }

    // MARK: - Docker

    var dockerReclaimableBytes: UInt64 {
        state.categoryResults[.docker]?.totalSizeBytes ?? 0
    }

    func requestDockerPrune() {
        guard dockerReclaimableBytes > 0, !isPruningDocker else { return }
        showDockerPruneConfirmation = true
    }

    func cancelDockerPruneConfirmation() {
        showDockerPruneConfirmation = false
    }

    func performDockerPrune() {
        let estimatedBytes = dockerReclaimableBytes
        showDockerPruneConfirmation = false
        guard estimatedBytes > 0, !isPruningDocker else { return }
        isPruningDocker = true
        Task {
            let records = await service.pruneDocker(estimatedBytes: estimatedBytes)
            let succeeded = records.filter { if case .succeeded = $0.result { return true } else { return false } }
            let failed = records.filter { if case .failed = $0.result { return true } else { return false } }
            let refused = records.filter { if case .refused = $0.result { return true } else { return false } }
            let bytes = succeeded.reduce(UInt64(0)) { $0 + $1.sizeBytes }
            self.lastCleanupSummary = CleanupSummary(
                kind: .docker,
                succeeded: succeeded.count,
                failed: failed.count,
                refused: refused.count,
                totalBytes: bytes,
                completedAt: .now
            )
            self.isPruningDocker = false
        }
    }

    // MARK: - Full Disk Access

    func recheckFullDiskAccess() {
        Task { await service.recheckFullDiskAccess() }
    }

    func openFullDiskAccessSettings() {
        service.openFullDiskAccessSettings()
    }
}
