import SwiftUI

/// Bottom action bar surfaced at the bottom of the Storage tab whenever the user
/// has at least one item selected. Hidden otherwise.
struct StickyCleanBar: View {
    let selectedCount: Int
    let selectedBytes: UInt64
    let isCleaning: Bool
    let onClean: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedCount) item\(selectedCount == 1 ? "" : "s") selected")
                    .font(.callout.weight(.semibold))
                Text(ByteFormatting.memory(selectedBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button("Deselect All", action: onClear)
                .buttonStyle(.bordered)
                .disabled(isCleaning)

            Button {
                onClean()
            } label: {
                if isCleaning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Cleaning…")
                            .font(.callout.weight(.semibold))
                    }
                } else {
                    Label("Clean", systemImage: "trash")
                        .font(.callout.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(isCleaning)
            .help("Review and clean selected items (⌘⌫)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.separator),
            alignment: .top
        )
    }
}
