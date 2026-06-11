import SwiftUI

/// Modal confirmation shown before any cleanup. Always required, even for Trash-mode.
/// Mirrors the KillConfirmDialog layout.
struct CleanConfirmationDialog: View {
    let items: [CleanableItem]
    let onCancel: () -> Void
    let onClean: (DeletionMode) -> Void

    @State private var mode: DeletionMode = .trash
    @State private var showAdvanced: Bool = false

    private var totalBytes: UInt64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    private var topFive: [CleanableItem] {
        items.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(5).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: mode == .trash ? "trash" : "exclamationmark.octagon.fill")
                    .font(.title)
                    .foregroundStyle(mode == .trash ? .orange : .red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clean \(ByteFormatting.memory(totalBytes))?")
                        .font(.title2.weight(.semibold))
                    Text("\(items.count) item\(items.count == 1 ? "" : "s") will be \(mode == .trash ? "moved to the Trash" : "deleted permanently").")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !topFive.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Largest items")
                        .font(.headline)
                    ForEach(topFive) { item in
                        HStack {
                            Text(item.displayName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(item.sizeFormatted)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                    if items.count > topFive.count {
                        Text("…and \(items.count - topFive.count) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Deletion mode", selection: $mode) {
                        Text("Move to Trash (recoverable)").tag(DeletionMode.trash)
                        Text("Delete Permanently").tag(DeletionMode.permanent)
                        Text("Delete Permanently with Admin").tag(DeletionMode.adminPermanent)
                    }
                    .pickerStyle(.radioGroup)
                    .padding(.top, 6)

                    Text(modeExplainer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } label: {
                Label("Advanced", systemImage: "gearshape")
                    .font(.headline)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button {
                    onClean(mode)
                } label: {
                    Text(mode == .trash ? "Move to Trash" : "Delete Permanently")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(mode == .trash ? .accentColor : .red)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private var modeExplainer: String {
        switch mode {
        case .trash:
            return "Files will be moved to ~/.Trash. You can restore them from Finder."
        case .permanent:
            return "Files will be removed immediately. They will not appear in the Trash and cannot be recovered."
        case .adminPermanent:
            return "Permanent delete plus a one-time administrator prompt for any locked system files. Only files inside the allowed system-cache directories will be escalated."
        }
    }
}
