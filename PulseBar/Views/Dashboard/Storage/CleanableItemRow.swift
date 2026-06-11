import SwiftUI
import AppKit

/// One file row in `CategoryDetailView`.
struct CleanableItemRow: View {
    let item: CleanableItem
    let isSelected: Bool
    let isSelectable: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isSelectable {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "eye")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, height: 22)
                    .help("Reveal-only — this category is informational")
            }

            Image(systemName: "doc")
                .foregroundStyle(.secondary)

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

            Spacer(minLength: 12)

            Text(item.sizeFormatted)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { if isSelectable { toggle() } }
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
        }
    }
}
