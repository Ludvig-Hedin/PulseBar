import SwiftUI
import AppKit

/// Detail for one saved scan. Lazily loads the fat snapshot file and shows the
/// disk state at scan time, the per-category breakdown, the top folders, and the
/// biggest items.
struct ScanSnapshotDetailView: View {
    let snapshotID: UUID
    @EnvironmentObject private var history: ScanHistoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var snapshot: ScanSnapshot?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        summary(snapshot)
                        categoryBreakdown(snapshot)
                        topFolders(snapshot)
                        topItems(snapshot)
                    }
                    .padding(20)
                }
            } else {
                Text("This scan's details couldn't be loaded.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 620, height: 640)
        .task {
            snapshot = await history.loadSnapshot(id: snapshotID)
            loading = false
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.map { $0.tier.title } ?? "Scan")
                    .font(.title2.weight(.semibold))
                if let snapshot {
                    Text(snapshot.finishedAt.formatted(date: .complete, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private func summary(_ s: ScanSnapshot) -> some View {
        HStack(spacing: 16) {
            metric("Junk found", ByteFormatting.memory(s.totalJunkBytes), .orange)
            metric("Free at scan", ByteFormatting.gigabytes(s.diskFreeBytes), .green)
            metric("Items", s.topItems.count == 0 ? "0" : "\(s.categories.reduce(0) { $0 + $1.itemCount })", .primary)
        }
    }

    private func metric(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(tint).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func categoryBreakdown(_ s: ScanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By category").font(.title3.weight(.semibold))
            ForEach(s.categories.sorted { $0.totalSizeBytes > $1.totalSizeBytes }) { c in
                HStack(spacing: 10) {
                    Image(systemName: c.category.symbol).foregroundStyle(c.category.tint).frame(width: 20)
                    Text(c.category.title).font(.callout)
                    Spacer()
                    Text("\(c.itemCount.formatted()) items").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Text(ByteFormatting.memory(c.totalSizeBytes)).font(.callout.weight(.medium)).monospacedDigit()
                        .frame(minWidth: 76, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private func topFolders(_ s: ScanSnapshot) -> some View {
        if !s.folders.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Top folders").font(.title3.weight(.semibold))
                ForEach(s.folders.prefix(10)) { folder in
                    HStack(spacing: 10) {
                        Image(systemName: folder.dominantCategory.symbol)
                            .foregroundStyle(folder.dominantCategory.tint).frame(width: 20)
                        Text(folder.displayPath).font(.callout).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(ByteFormatting.memory(folder.sizeBytes)).font(.callout.weight(.medium)).monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func topItems(_ s: ScanSnapshot) -> some View {
        if !s.topItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Biggest items").font(.title3.weight(.semibold))
                ForEach(s.topItems.prefix(15)) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.isDirectory ? "folder" : "doc")
                            .foregroundStyle(.secondary).frame(width: 20)
                        Text(item.displayName).font(.callout).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(ByteFormatting.memory(item.sizeBytes)).font(.callout.weight(.medium)).monospacedDigit()
                    }
                }
            }
        }
    }
}
