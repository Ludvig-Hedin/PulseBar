import SwiftUI
import AppKit

/// Flat list of ALL scanned items across every cleanable category, sorted by size.
/// Fastest path from "scan done" to "items deleted": no per-category drill-down required.
struct AllFilesView: View {
    @EnvironmentObject private var storageVM: StorageViewModel

    var body: some View {
        if storageVM.isScanRunning {
            scanningState
        } else if let category = storageVM.fileCategoryFilter {
            categoryContent(category)
        } else if !storageVM.state.hasFreshScan {
            noScanState
        } else {
            fileList(category: nil, includeRevealOnly: false)
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

    private func noCategoryScanState(_ category: StorageCategory) -> some View {
        VStack(spacing: 16) {
            Image(systemName: category.symbol)
                .font(.system(size: 44))
                .foregroundStyle(category.tint)
            Text("\(category.title) has not been scanned")
                .font(.title3.weight(.semibold))
            Text("Scan this category to review its current storage impact.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    storageVM.startScan([category])
                } label: {
                    Label("Scan \(category.title)", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button("Show All Cleanable Files") {
                    storageVM.showFiles()
                }
                .buttonStyle(.bordered)
            }
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

    @ViewBuilder
    private func categoryContent(_ category: StorageCategory) -> some View {
        switch StorageViewModel.actionKind(for: category) {
        case .cleanable:
            if storageVM.state.categoryResults[category] == nil {
                noCategoryScanState(category)
            } else {
                fileList(category: category, includeRevealOnly: false)
            }
        case .revealOnly:
            if storageVM.state.categoryResults[category] == nil {
                noCategoryScanState(category)
            } else {
                fileList(category: category, includeRevealOnly: true)
            }
        case .externalAction:
            if storageVM.state.categoryResults[category] == nil {
                noCategoryScanState(category)
            } else {
                dockerActionState
            }
        case .informational:
            if storageVM.state.categoryResults[category] == nil {
                noCategoryScanState(category)
            } else {
                informationalState(category)
            }
        }
    }

    private func fileList(category: StorageCategory?, includeRevealOnly: Bool) -> some View {
        let items = storageVM.allItemsSorted(category: category,
                                             searchText: storageVM.searchText,
                                             includeRevealOnly: includeRevealOnly)
        return VStack(spacing: 0) {
            toolbar(category: category,
                    includeRevealOnly: includeRevealOnly,
                    visibleItemCount: items.count)
            Divider()
            if items.isEmpty {
                emptyResultsState(category: category, includeRevealOnly: includeRevealOnly)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(items) { item in
                            AllFileRow(
                                item: item,
                                isSelected: storageVM.selectedItems.contains(item.url),
                                isSelectable: StorageViewModel.isCleanable(item.category),
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

    private func toolbar(category: StorageCategory?, includeRevealOnly: Bool, visibleItemCount: Int) -> some View {
        HStack(spacing: 8) {
            SearchBar(text: $storageVM.searchText, placeholder: category == nil ? "Search all files" : "Search \(category?.title ?? "files")")

            if let category {
                Button {
                    storageVM.showFiles()
                } label: {
                    Label(category.title, systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .help("Clear category filter")
            }

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

            if includeRevealOnly {
                Text("Reveal-only")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Button("Select Visible") { storageVM.selectAllVisibleReviewItems() }
                    .buttonStyle(.bordered)
                    .disabled(visibleItemCount == 0)

                Button("Deselect Visible") { storageVM.deselectAllVisibleReviewItems() }
                    .buttonStyle(.bordered)
                    .disabled(visibleItemCount == 0)

                if storageVM.selectedTotalCount > 0 {
                    Text("\(storageVM.selectedTotalCount) selected · \(ByteFormatting.memory(storageVM.selectedTotalBytes))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Button {
                        storageVM.requestCleanup()
                    } label: {
                        Label("Clean Selected", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(storageVM.isCleaning)
                    .help("Review and clean selected items")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func emptyResultsState(category: StorageCategory?, includeRevealOnly: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: includeRevealOnly ? "doc.text.magnifyingglass" : "checkmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(emptyTitle(category: category, includeRevealOnly: includeRevealOnly))
                .font(.headline)
            Text(emptySubtitle(category: category, includeRevealOnly: includeRevealOnly))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                if !storageVM.searchText.isEmpty {
                    Button("Clear Search") {
                        storageVM.searchText = ""
                    }
                    .buttonStyle(.bordered)
                }
                if let category {
                    Button {
                        storageVM.startScan([category])
                    } label: {
                        Label("Scan Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private func emptyTitle(category: StorageCategory?, includeRevealOnly: Bool) -> String {
        if !storageVM.searchText.isEmpty {
            return "No results for \"\(storageVM.searchText)\""
        }
        if includeRevealOnly {
            return "No large files found"
        }
        if let category {
            return "No cleanable files in \(category.title)"
        }
        return "Nothing to clean"
    }

    private func emptySubtitle(category: StorageCategory?, includeRevealOnly: Bool) -> String {
        if !storageVM.searchText.isEmpty {
            return "Clear the search or scan again to review more files."
        }
        if includeRevealOnly {
            return "PulseBar did not find large files in the scanned dev-tooling locations."
        }
        if let category {
            return "\(category.title) is already clean based on the latest scan."
        }
        return "Smart Scan did not find deletable cache, log, Trash, or dev-artifact files."
    }

    private var dockerActionState: some View {
        let result = storageVM.state.categoryResults[.docker]
        let bytes = result?.totalSizeBytes ?? 0
        let unavailable = result?.errors.isEmpty == false
        return VStack(spacing: 16) {
            Image(systemName: "cube.box")
                .font(.system(size: 46))
                .foregroundStyle(StorageCategory.docker.tint)
            Text(dockerTitle(bytes: bytes, unavailable: unavailable))
                .font(.title3.weight(.semibold))
            Text(dockerSubtitle(bytes: bytes, unavailable: unavailable))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            HStack(spacing: 10) {
                Button {
                    storageVM.startScan([.docker])
                } label: {
                    Label("Scan Docker", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(storageVM.isPruningDocker)

                if bytes > 0 {
                    Button {
                        storageVM.requestDockerPrune()
                    } label: {
                        Label(storageVM.isPruningDocker ? "Pruning…" : "Prune Docker", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(storageVM.isPruningDocker)
                }

                Button("Show All Cleanable Files") {
                    storageVM.showFiles()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func dockerTitle(bytes: UInt64, unavailable: Bool) -> String {
        if bytes > 0 { return "Docker prune available" }
        if unavailable { return "Docker not running" }
        return "No Docker cleanup needed"
    }

    private func dockerSubtitle(bytes: UInt64, unavailable: Bool) -> String {
        if bytes > 0 {
            return "\(ByteFormatting.memory(bytes)) is reported as reclaimable by Docker. PulseBar runs `docker system prune -f`, which does not remove Docker volumes."
        }
        if unavailable {
            return "Docker CLI is unavailable or the Docker daemon is not running. Start Docker, then scan again."
        }
        return "Docker is not reporting reclaimable images, containers, networks, or build cache right now."
    }

    private func informationalState(_ category: StorageCategory) -> some View {
        let result = storageVM.state.categoryResults[category]
        let bytes = result?.totalSizeBytes ?? 0
        return VStack(spacing: 16) {
            Image(systemName: category.symbol)
                .font(.system(size: 46))
                .foregroundStyle(category.tint)
            Text(category == .purgeableSpace ? "Managed by macOS" : category.title)
                .font(.title3.weight(.semibold))
            Text(informationalSubtitle(category, bytes: bytes))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            HStack(spacing: 10) {
                Button {
                    storageVM.startScan([category])
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button("Show All Cleanable Files") {
                    storageVM.showFiles()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func informationalSubtitle(_ category: StorageCategory, bytes: UInt64) -> String {
        if category == .purgeableSpace {
            let amount = bytes > 0 ? "\(ByteFormatting.memory(bytes)) is currently purgeable. " : ""
            return amount + "macOS reclaims this space automatically when apps need room, so PulseBar does not show it as deletable files."
        }
        return category.subtitle
    }
}

// MARK: - Row

private struct AllFileRow: View {
    let item: CleanableItem
    let isSelected: Bool
    let isSelectable: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rowIcon)
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

            if !isSelectable {
                Button {
                    revealInFinder()
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { if isSelectable { toggle() } }
        .contextMenu {
            Button {
                revealInFinder()
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
            if isSelectable {
                Divider()
                Button(role: .destructive) {
                    toggle()
                } label: {
                    Label(isSelected ? "Deselect" : "Select for Cleanup", systemImage: isSelected ? "minus.square" : "checkmark.square")
                }
            }
        }
    }

    private var rowIcon: String {
        if isSelectable { return isSelected ? "checkmark.square.fill" : "square" }
        return "eye"
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
}
