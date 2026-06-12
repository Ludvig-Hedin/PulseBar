import SwiftUI
import AppKit

/// Flat list of ALL scanned items across every cleanable category, sorted by size.
/// Fastest path from "scan done" to "items deleted": no per-category drill-down required.
struct AllFilesView: View {
    @EnvironmentObject private var storageVM: StorageViewModel
    @State private var localSearch: String = ""

    var body: some View {
        if storageVM.isScanRunning {
            scanningState
        } else if !storageVM.state.hasFreshScan {
            noScanState
        } else {
            fileList
        }
    }

    // MARK: - States

    private var noScanState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No scan results yet")
                .font(.title3.weight(.semibold))
            Text("Run Smart Scan to see all files sorted by size.")
                .foregroundStyle(.secondary)
            Button {
                storageVM.startSmartScan()
            } label: {
                Label("Run Smart Scan", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Scanning…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File list

    private var fileList: some View {
        let items = storageVM.allItemsSorted(searchText: localSearch)
        return VStack(spacing: 0) {
            toolbar(totalItemCount: storageVM.allItemsSorted().count)
            Divider()
            if items.isEmpty {
                Text(localSearch.isEmpty ? "Nothing to clean" : "No results for \"\(localSearch)\"")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(items) { item in
                            AllFileRow(
                                item: item,
                                isSelected: storageVM.selectedItems.contains(item.url),
                                toggle: { storageVM.toggleSelection(item.url) }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func toolbar(totalItemCount: Int) -> some View {
        HStack(spacing: 8) {
            SearchBar(text: $localSearch, placeholder: "Search all files")

            Menu {
                Picker("Sort by", selection: $storageVM.sortColumn) {
                    ForEach(StorageViewModel.SortColumn.allCases) { col in
                        Text(col.rawValue).tag(col)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                    Text("Sort: \(storageVM.sortColumn.rawValue)")
                }
                .font(.callout)
            }
            .menuStyle(.button)
            .fixedSize()

            Button {
                storageVM.sortDirection = storageVM.sortDirection == .descending ? .ascending : .descending
            } label: {
                Text(storageVM.sortDirection == .descending ? "↓" : "↑")
                    .font(.callout.weight(.semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.bordered)
            .help(storageVM.sortDirection == .descending ? "Largest first — click to reverse" : "Smallest first — click to reverse")

            Divider().frame(height: 20)

            Button("Select All") { storageVM.selectAllCleanable() }
                .buttonStyle(.bordered)
            Button("Deselect All") { storageVM.clearSelection() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Row

private struct AllFileRow: View {
    let item: CleanableItem
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body)
                    .lineLimit(1)
                Text(item.parentDirectory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            // Category badge
            Text(item.category.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(item.category.tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(item.category.tint.opacity(0.12))
                .clipShape(Capsule())
                .lineLimit(1)

            Text(item.sizeFormatted)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { toggle() }
        .contextMenu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Label("Reveal in Finder", systemImage: "magnifyingglass.circle")
            }
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(item.url.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive) {
                toggle()   // ensure selected, then let user confirm via StickyCleanBar
            } label: {
                Label(isSelected ? "Deselect" : "Select for Cleanup", systemImage: isSelected ? "minus.square" : "checkmark.square")
            }
        }
    }
}
