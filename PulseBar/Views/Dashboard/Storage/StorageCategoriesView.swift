import SwiftUI

/// Categories list. Tapping a row drills into `CategoryDetailView`.
struct StorageCategoriesView: View {
    @EnvironmentObject private var storageVM: StorageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            smartScanCard

            if showCleanSystemBanner {
                cleanSystemBanner
            }

            LazyVStack(spacing: 10) {
                ForEach(StorageCategory.displayedCategories, id: \.self) { category in
                    CategoryRow(
                        category: category,
                        result: storageVM.state.categoryResults[category],
                        isScanning: isScanning(category),
                        runningBytes: storageVM.state.scanProgress?.runningTotals[category],
                        runningCount: storageVM.state.scanProgress?.runningCounts[category],
                        needsFullDiskAccess: category.requiresFullDiskAccess
                            && storageVM.state.fullDiskAccessGranted == false,
                        onTap: { storageVM.selectedCategory = category },
                        onSelectAll: { storageVM.selectAll(in: category) },
                        onDeselectAll: { storageVM.deselectAll(in: category) },
                        selectedCount: selectedCount(in: category),
                        totalCount: storageVM.state.categoryResults[category]?.itemCount ?? 0
                    )
                }
            }
        }
        .sheet(item: $storageVM.selectedCategory) { category in
            CategoryDetailView(category: category)
                .environmentObject(storageVM)
                .frame(minWidth: 720, minHeight: 520)
        }
    }

    private var smartScanCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "wand.and.stars")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Smart Scan")
                    .font(.title3.weight(.semibold))
                Text("Scan caches, logs, Trash, Mail Downloads, and dev artifacts in one sweep.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button {
                storageVM.startSmartScan()
            } label: {
                Label(storageVM.isScanRunning ? "Scanning…" : "Run Smart Scan", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(storageVM.isScanRunning)
        }
        .padding(18)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func isScanning(_ category: StorageCategory) -> Bool {
        guard let progress = storageVM.state.scanProgress else { return false }
        return progress.currentCategory == category && !progress.completed.contains(category)
    }

    private func selectedCount(in category: StorageCategory) -> Int {
        guard let result = storageVM.state.categoryResults[category] else { return 0 }
        return result.items.reduce(0) { $0 + (storageVM.selectedItems.contains($1.url) ? 1 : 0) }
    }

    /// Show the celebratory banner only when a scan has finished, no scan is running,
    /// and the deletable totals are genuinely zero.
    private var showCleanSystemBanner: Bool {
        guard !storageVM.isScanRunning else { return false }
        guard storageVM.state.hasFreshScan else { return false }
        return storageVM.state.totalJunkBytes == 0
    }

    private var cleanSystemBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing to clean")
                    .font(.body.weight(.semibold))
                Text("Smart Scan didn't find any deletable junk. Run it again later to pick up new caches and dev artifacts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.green.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.green.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
