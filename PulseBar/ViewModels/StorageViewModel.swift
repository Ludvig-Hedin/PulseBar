import Foundation
import Combine

/// Storage-tab UI facade over `StorageService`. Owns selection + filtering state
/// that's irrelevant outside the Storage tab.
@MainActor
final class StorageViewModel: ObservableObject {
    enum Subview: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case categories = "Categories"
        case settings = "Settings"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .dashboard: return "chart.pie"
            case .categories: return "tray.full"
            case .settings: return "slider.horizontal.3"
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

    let service: StorageService

    /// Republished so views can observe `StorageViewModel` alone.
    @Published private(set) var diskUsage: DiskUsage?
    @Published private(set) var state = StorageState()

    // MARK: - UI selection state

    /// Categories is the actionable surface (Smart Scan card + category list).
    /// Dashboard is informational; defaulting there makes users hunt for the cleanup
    /// flow. First-time users land on the action, not on a hero gauge with empty stats.
    @Published var subview: Subview = .categories
    @Published var selectedCategory: StorageCategory?
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

    struct CleanupSummary: Equatable {
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
        clearSelection()
        service.startScan([.smartScan])
    }

    func startScan(_ categories: [StorageCategory]) {
        clearSelection()
        service.startScan(categories)
    }

    func cancelScan() { service.cancelScan() }

    var isScanRunning: Bool { state.scanProgress != nil }

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
        // Reveal-only categories can't be cleaned anyway; selection in those is a no-op
        // gated by `selectedCleanables`.
        guard !Self.isRevealOnly(category) else { return }
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

    /// Items the user has selected across all categories. Used by the Clean flow.
    /// Reveal-only categories (Large Files, Purgeable, Docker synthetic) are
    /// excluded as a safety belt: the UI hides their selection control too,
    /// but this filter is the authoritative gate.
    var selectedCleanables: [CleanableItem] {
        var out: [CleanableItem] = []
        for result in state.categoryResults.values {
            for item in result.items where selectedItems.contains(item.url) {
                if Self.isRevealOnly(item.category) { continue }
                out.append(item)
            }
        }
        return out
    }

    /// True for categories where items are display-only — the cleaner refuses to
    /// touch them via the normal Clean flow.
    static func isRevealOnly(_ category: StorageCategory) -> Bool {
        switch category {
        case .largeFiles, .purgeableSpace, .docker: return true
        default: return false
        }
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

    // MARK: - Full Disk Access

    func recheckFullDiskAccess() {
        Task { await service.recheckFullDiskAccess() }
    }

    func openFullDiskAccessSettings() {
        service.openFullDiskAccessSettings()
    }
}
