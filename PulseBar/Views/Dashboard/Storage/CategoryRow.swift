import SwiftUI

/// One row in the Storage categories list.
struct CategoryRow: View {
    let category: StorageCategory
    let result: CategoryResult?
    let isScanning: Bool
    let runningBytes: UInt64?
    let runningCount: Int?
    let needsFullDiskAccess: Bool
    let onTap: () -> Void
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void
    let selectedCount: Int
    let totalCount: Int

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(category.tint.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: category.symbol)
                        .font(.title3)
                        .foregroundStyle(category.tint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(category.title)
                            .font(.body.weight(.semibold))
                        if needsFullDiskAccess {
                            Image(systemName: "lock.shield.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .help("Full Disk Access required to read all paths in this category")
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Text(sizeText)
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                    if itemCountText.isEmpty == false {
                        Text(itemCountText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .help("Open details")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if totalCount > 0 {
                Button("Select All", action: onSelectAll)
                Button("Deselect All", action: onDeselectAll)
            }
        }
    }

    private var subtitle: String {
        if isScanning { return "Scanning…" }
        if let result, result.errors.contains(where: { $0.reason == .permissionDenied }) {
            return "Full Disk Access required for some paths"
        }
        return category.subtitle
    }

    private var sizeText: String {
        if let result {
            return result.totalFormatted
        }
        if let running = runningBytes {
            return ByteFormatting.memory(running)
        }
        return "—"
    }

    private var itemCountText: String {
        if let count = runningCount, isScanning { return "\(count) items" }
        guard let result else { return "" }
        if result.itemCount == 0 { return "Nothing to clean" }
        if selectedCount > 0 { return "\(selectedCount) of \(result.itemCount) selected" }
        return "\(result.itemCount) items"
    }
}
