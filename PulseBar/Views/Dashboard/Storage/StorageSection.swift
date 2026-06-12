import SwiftUI
import AppKit

/// Storage tab root. Hosts the FDA banner, sub-view picker, sticky clean bar,
/// and the modal cleanup confirmation.
struct StorageSection: View {
    @EnvironmentObject private var storageVM: StorageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if storageVM.state.fullDiskAccessGranted == false {
                FullDiskAccessBanner(
                    onOpenSettings: { storageVM.openFullDiskAccessSettings() },
                    onRecheck: { storageVM.recheckFullDiskAccess() }
                )
            }

            if let summary = storageVM.lastCleanupSummary {
                cleanupSummaryCard(summary)
            }

            // Always-visible scan progress so the user sees (and can cancel) work
            // regardless of which Storage sub-view they're on.
            LiveScanPanel()
                .environmentObject(storageVM)

            subviewPicker

            Group {
                switch storageVM.subview {
                case .dashboard:
                    StorageDashboardView()
                        .environmentObject(storageVM)
                case .files:
                    AllFilesView()
                        .environmentObject(storageVM)
                case .categories:
                    StorageCategoriesView()
                        .environmentObject(storageVM)
                case .settings:
                    StorageSettingsView()
                        .environmentObject(storageVM)
                }
            }

            if storageVM.selectedTotalCount > 0 || storageVM.isCleaning {
                StickyCleanBar(
                    selectedCount: storageVM.selectedTotalCount,
                    selectedBytes: storageVM.selectedTotalBytes,
                    isCleaning: storageVM.isCleaning,
                    onClean: { storageVM.requestCleanup() },
                    onClear: { storageVM.clearSelection() }
                )
            }
        }
        .sheet(isPresented: $storageVM.showCleanConfirmation) {
            CleanConfirmationDialog(
                items: storageVM.selectedCleanables,
                onCancel: { storageVM.cancelCleanupConfirmation() },
                onClean: { mode in storageVM.performCleanup(mode: mode) }
            )
        }
    }

    private var subviewPicker: some View {
        Picker("View", selection: $storageVM.subview) {
            ForEach(StorageViewModel.Subview.allCases) { sub in
                Label(sub.rawValue, systemImage: sub.symbol).tag(sub)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 600)
    }

    private func cleanupSummaryCard(_ summary: StorageViewModel.CleanupSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Reclaimed \(summary.totalFormatted)")
                    .font(.body.weight(.semibold))
                Text("\(summary.succeeded) deleted · \(summary.failed) failed · \(summary.refused) refused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Trash-mode cleanups are recoverable — make finding them one click away.
            if summary.succeeded > 0 {
                Button {
                    let trash = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".Trash", isDirectory: true)
                    NSWorkspace.shared.open(trash)
                } label: {
                    Label("Show in Trash", systemImage: "trash")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
            Button {
                storageVM.lastCleanupSummary = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(14)
        .background(Color.green.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.green.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: summary.completedAt) {
            // Auto-dismiss the toast after 8s so it doesn't haunt the screen between
            // unrelated scans. Cancelled if a new summary lands (different completedAt).
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if storageVM.lastCleanupSummary?.completedAt == summary.completedAt {
                storageVM.lastCleanupSummary = nil
            }
        }
    }

}
