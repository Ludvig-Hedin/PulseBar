import SwiftUI
import AppKit

/// Storage tab Settings sub-view. Surfaces FDA state, deletion log, and the
/// PureMac attribution.
struct StorageSettingsView: View {
    @EnvironmentObject private var storageVM: StorageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            fullDiskAccessCard
            deletionLogCard
            attributionCard
        }
    }

    private var fullDiskAccessCard: some View {
        let granted = storageVM.state.fullDiskAccessGranted
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: granted == true ? "checkmark.shield.fill" : "lock.shield")
                    .font(.title2)
                    .foregroundStyle(granted == true ? .green : .orange)
                Text("Full Disk Access")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(granted == true ? "Granted" : (granted == false ? "Missing" : "Checking…"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(granted == true ? .green : .secondary)
            }
            Text("Required to scan Mail Downloads, browser caches, and system logs. Other categories work without it.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    storageVM.openFullDiskAccessSettings()
                } label: {
                    Label("Open System Settings", systemImage: "gearshape")
                }
                Button("Re-check") {
                    storageVM.recheckFullDiskAccess()
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var deletionLogCard: some View {
        let records = storageVM.state.recentDeletions.reversed()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recent Deletions", systemImage: "clock.arrow.circlepath")
                    .font(.title3.weight(.semibold))
                Spacer()
                if !storageVM.state.recentDeletions.isEmpty {
                    Button("Clear") {
                        storageVM.service.clearDeletionHistory()
                    }
                    .buttonStyle(.borderless)
                }
            }
            if storageVM.state.recentDeletions.isEmpty {
                Text("Nothing deleted yet. Records appear here after you run a cleanup.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(records.prefix(50))) { record in
                            deletionRow(record)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func deletionRow(_ record: DeletionRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: record.result.isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(record.result.isSuccess ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(record.category.title) · \(record.mode.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(record.sizeFormatted)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([record.url])
            }
        }
    }

    private var attributionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Attribution", systemImage: "doc.text")
                .font(.title3.weight(.semibold))
            Text("Cleaning categories, scan-engine architecture, and Full Disk Access detection are adapted from PureMac (MIT). See THIRD_PARTY_LICENSES.md for the original license.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
