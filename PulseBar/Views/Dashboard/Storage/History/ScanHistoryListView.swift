import SwiftUI

/// Newest-first list of saved scans with a per-scan junk delta. Tapping a row
/// opens its detail sheet; a toolbar action clears all history.
struct ScanHistoryListView: View {
    @EnvironmentObject private var history: ScanHistoryStore
    @State private var selectedID: UUID?
    @State private var showClearConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(history.index.count) saved scan\(history.index.count == 1 ? "" : "s")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) { showClearConfirm = true } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(history.index.isEmpty)
            }

            LazyVStack(spacing: 8) {
                ForEach(Array(history.index.enumerated()), id: \.element.id) { index, entry in
                    // Previous (older) scan is the next one in the newest-first array.
                    let previous = index + 1 < history.index.count ? history.index[index + 1] : nil
                    ScanHistoryRow(entry: entry, previous: previous)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedID = entry.id }
                        .contextMenu {
                            Button(role: .destructive) { history.delete(id: entry.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .sheet(item: Binding(get: { selectedID.map { IdentifiedID(id: $0) } },
                             set: { selectedID = $0?.id })) { wrapper in
            ScanSnapshotDetailView(snapshotID: wrapper.id)
                .environmentObject(history)
        }
        .confirmationDialog("Delete all saved scans?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { history.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved scan and its trend data. It can't be undone.")
        }
    }
}

/// Sheet-item wrapper so a bare UUID can drive `.sheet(item:)`.
private struct IdentifiedID: Identifiable { let id: UUID }

struct ScanHistoryRow: View {
    let entry: ScanSnapshotIndexEntry
    let previous: ScanSnapshotIndexEntry?

    var body: some View {
        HStack(spacing: 14) {
            tierBadge

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.finishedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.callout.weight(.medium))
                Text("\(entry.itemCountTotal.formatted()) items · \(Int(entry.durationSeconds))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            deltaChip

            Text(ByteFormatting.memory(entry.totalJunkBytes))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 80, alignment: .trailing)

            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tierBadge: some View {
        Text(entry.tier.title.replacingOccurrences(of: " Scan", with: ""))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            .foregroundStyle(Color.accentColor)
    }

    @ViewBuilder
    private var deltaChip: some View {
        if let previous {
            let diff = Int64(bitPattern: entry.totalJunkBytes) - Int64(bitPattern: previous.totalJunkBytes)
            if diff != 0 {
                let up = diff > 0
                HStack(spacing: 3) {
                    Image(systemName: up ? "arrow.up" : "arrow.down")
                    Text(ByteFormatting.memory(UInt64(abs(diff))))
                }
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(up ? .orange : .green)
            }
        }
    }
}
