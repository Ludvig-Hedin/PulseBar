import SwiftUI

/// Drill-down view for a single category. Searchable + sortable per-item list.
struct CategoryDetailView: View {
    let category: StorageCategory
    @EnvironmentObject private var storageVM: StorageViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if isScanningThisCategory {
                EmptyStateView(title: "Scanning \(category.title)…",
                               subtitle: "Items will appear as they're found.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = storageVM.state.categoryResults[category], result.items.isEmpty {
                EmptyStateView(title: result.errors.isEmpty ? "Nothing to clean" : "No accessible items found",
                               subtitle: result.errors.isEmpty
                                 ? "This category is already clean. Try another."
                                 : "Some paths couldn't be read. Grant Full Disk Access for a complete scan.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if storageVM.state.categoryResults[category] == nil {
                EmptyStateView(title: "Not scanned yet",
                               subtitle: "Run a Smart Scan to populate this category.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                listView
            }

            Divider()

            footer
        }
        .frame(minWidth: 720, minHeight: 520)
        .sheet(isPresented: $storageVM.showCleanConfirmation) {
            CleanConfirmationDialog(
                items: storageVM.selectedCleanables,
                onCancel: { storageVM.cancelCleanupConfirmation() },
                onClean: { mode in
                    storageVM.performCleanup(mode: mode)
                    dismiss()
                }
            )
        }
    }

    private var isScanningThisCategory: Bool {
        guard let progress = storageVM.state.scanProgress else { return false }
        return progress.currentCategory == category && !progress.completed.contains(category)
    }

    private var hasPermissionErrors: Bool {
        storageVM.state.categoryResults[category]?.errors.contains { $0.reason == .permissionDenied } ?? false
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: category.symbol)
                .font(.title)
                .foregroundStyle(category.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .font(.title2.weight(.semibold))
                Text(category.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                // `.sheet(item:)` clears `selectedCategory` when this view tears down,
                // so we only need to dismiss. Setting selectedCategory to nil here
                // would race with the framework's own write.
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private var listView: some View {
        VStack(spacing: 0) {
            // Reveal-only context appears BEFORE the toolbar so the user knows the
            // selection controls below are intentionally absent.
            if StorageViewModel.isRevealOnly(category) {
                revealOnlyBanner
                    .padding(.top, 12)
            }

            if hasPermissionErrors {
                permissionErrorsBanner
                    .padding(.top, 12)
            }

            HStack(spacing: 8) {
                SearchBar(text: $storageVM.searchText, placeholder: "Search files")

                // Column picker
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

                // Direction toggle — single click flips order
                Button {
                    storageVM.sortDirection = storageVM.sortDirection == .descending ? .ascending : .descending
                } label: {
                    Text(storageVM.sortDirection == .descending ? "↓" : "↑")
                        .font(.callout.weight(.semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.bordered)
                .help(storageVM.sortDirection == .descending ? "Largest first — click to reverse" : "Smallest first — click to reverse")

                if !StorageViewModel.isRevealOnly(category) {
                    Button("Select All") { storageVM.selectAll(in: category) }
                        .buttonStyle(.bordered)
                    Button("Deselect All") { storageVM.deselectAll(in: category) }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(storageVM.filteredItems(for: category)) { item in
                        CleanableItemRow(
                            item: item,
                            isSelected: storageVM.selectedItems.contains(item.url),
                            isSelectable: !StorageViewModel.isRevealOnly(category),
                            toggle: { storageVM.toggleSelection(item.url) }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
    }

    private var permissionErrorsBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Some paths couldn't be read")
                    .font(.callout.weight(.semibold))
                Text("Grant Full Disk Access in Settings to scan this category completely. The items below are what we could see.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open Settings") {
                storageVM.openFullDiskAccessSettings()
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.orange.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var revealOnlyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(revealOnlyTitle)
                    .font(.callout.weight(.semibold))
                Text(revealOnlyExplainer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var revealOnlyTitle: String {
        switch category {
        case .largeFiles:     return "Reveal-only category"
        case .purgeableSpace: return "macOS handles this automatically"
        case .docker:         return "Manage Docker space from Docker CLI"
        default:              return ""
        }
    }

    private var revealOnlyExplainer: String {
        switch category {
        case .largeFiles:
            return "Large Files surfaces big files in your dev tooling folders so you can decide what to keep. Use \"Reveal in Finder\" to delete manually."
        case .purgeableSpace:
            return "Purgeable space is reclaimed automatically when macOS needs the room. There is nothing to delete from here."
        case .docker:
            return "Use `docker system prune -f` from a terminal to reclaim this space. PulseBar surfaces the number so you know it's there."
        default:
            return ""
        }
    }

    private var footer: some View {
        let result = storageVM.state.categoryResults[category]
        let selected = result?.items.filter { storageVM.selectedItems.contains($0.url) } ?? []
        let selectedBytes = selected.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        let isRevealOnly = StorageViewModel.isRevealOnly(category)
        return HStack(spacing: 12) {
            if let result {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(result.itemCount) item\(result.itemCount == 1 ? "" : "s") · \(result.totalFormatted) total")
                        .foregroundStyle(.secondary)
                    if result.truncated {
                        Text("Showing first \(result.items.count) — search to refine")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            if !selected.isEmpty {
                Text("\(selected.count) selected · \(ByteFormatting.memory(selectedBytes))")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                if !isRevealOnly {
                    Button {
                        storageVM.requestCleanup()
                    } label: {
                        Label("Clean Selected", systemImage: "trash")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.delete, modifiers: [.command])
                    .help("Review and clean selected items (⌘⌫)")
                }
            }
        }
        .padding(16)
    }
}
