import SwiftUI

/// Ultra Scan surface: a read-only, drill-down map of the whole disk. Shows the
/// biggest folders first with a size bar, file count, and age, so a non-expert
/// can find where space went. The only action is Reveal in Finder.
struct DiskInventoryView: View {
    @EnvironmentObject private var storageVM: StorageViewModel

    /// Breadcrumb stack. Last element is the folder currently shown.
    @State private var path: [InventoryNode] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if storageVM.isInventoryRunning {
                scanningState
            } else if let root = storageVM.inventoryRoot {
                content(root: root)
            } else {
                emptyState
            }
        }
        .onChange(of: storageVM.inventoryRoot) { _, newRoot in
            // Reset the breadcrumb whenever a fresh scan lands.
            path = newRoot.map { [$0] } ?? []
        }
        .onAppear {
            if path.isEmpty, let root = storageVM.inventoryRoot { path = [root] }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                storageVM.startUltraScan()
            } label: {
                Label(storageVM.isInventoryRunning ? "Mapping…" : "Ultra Scan", systemImage: "globe")
            }
            .buttonStyle(.borderedProminent)
            .disabled(storageVM.isInventoryRunning || storageVM.isScanRunning)

            if storageVM.isInventoryRunning {
                Button("Cancel", role: .destructive) { storageVM.cancelUltraScan() }
                    .buttonStyle(.bordered)
            }

            Spacer()
        }
    }

    // MARK: - States

    private var scanningState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Mapping every file on your disk…")
                    .font(.callout.weight(.medium))
            }
            if let progress = storageVM.inventoryProgress {
                Text("\(progress.scannedFiles.formatted()) files · \(ByteFormatting.memory(progress.scannedBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text("This reads the whole volume and can take a few minutes. Nothing is deleted.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Map your whole disk")
                .font(.title3.weight(.semibold))
            Text("Ultra Scan inventories every file to show where your space really went — big installs, forgotten downloads, old project folders. Read-only: it never deletes anything.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
            Text("Full Disk Access is recommended so it can see everything.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func content(root: InventoryNode) -> some View {
        let current = path.last ?? root
        VStack(alignment: .leading, spacing: 12) {
            breadcrumb(root: root)

            summaryLine(current)

            let children = current.topChildren
            if children.isEmpty {
                Text("No sub-folders large enough to break down here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                let maxBytes = children.map(\.totalBytes).max() ?? 1
                LazyVStack(spacing: 8) {
                    ForEach(children) { child in
                        InventoryRow(
                            node: child,
                            fractionOfMax: maxBytes > 0 ? Double(child.totalBytes) / Double(maxBytes) : 0,
                            onDrill: child.isNavigable ? { path.append(child) } : nil,
                            onReveal: child.isAggregate ? nil : { storageVM.revealInFinder(child.url) }
                        )
                    }
                }
            }
        }
    }

    private func breadcrumb(root: InventoryNode) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button {
                    path = Array(path.prefix(index + 1))
                } label: {
                    Text(node.displayName)
                        .font(.callout.weight(index == path.count - 1 ? .semibold : .regular))
                        .foregroundStyle(index == path.count - 1 ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func summaryLine(_ node: InventoryNode) -> some View {
        Text("\(ByteFormatting.memory(node.totalBytes)) · \(node.fileCount.formatted()) files")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}

/// One folder row in the disk map: name, size bar, size, file count, age, and
/// (for real folders) drill-in + Reveal.
private struct InventoryRow: View {
    let node: InventoryNode
    let fractionOfMax: Double
    let onDrill: (() -> Void)?
    let onReveal: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: node.isAggregate ? "ellipsis.circle" : (node.isNavigable ? "folder.fill" : "folder"))
                .foregroundStyle(node.isAggregate ? .tertiary : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(node.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(Color.accentColor.opacity(0.55))
                            .frame(width: max(2, geo.size.width * fractionOfMax))
                    }
                }
                .frame(height: 5)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormatting.memory(node.totalBytes))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text(ageLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 120, alignment: .trailing)

            if let onReveal {
                Button { onReveal() } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }

            if let onDrill {
                Button { onDrill() } label: {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                // Keep alignment when a row isn't navigable.
                Image(systemName: "chevron.right").foregroundStyle(.clear)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onDrill?() }
    }

    private var ageLabel: String {
        guard node.modifiedAt > .distantPast else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: node.modifiedAt, relativeTo: .now)
    }
}
