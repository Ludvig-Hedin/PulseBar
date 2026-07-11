import SwiftUI

/// Folders that keep filling up with junk across scans — the "where does my junk
/// keep coming from" view. Ranked by how often they recur.
struct RepeatOffendersView: View {
    @EnvironmentObject private var history: ScanHistoryStore
    @EnvironmentObject private var storageVM: StorageViewModel

    var body: some View {
        let offenders = history.repeatOffenders(minAppearances: 2)
        VStack(alignment: .leading, spacing: 12) {
            Text("Folders that keep filling up with junk across your scans.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if offenders.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(offenders) { offender in
                        RepeatOffenderRow(offender: offender,
                                          onReveal: { storageVM.revealInFinder(URL(fileURLWithPath: offender.displayPathExpanded)) })
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No repeat offenders yet")
                .font(.title3.weight(.semibold))
            Text("Once a folder shows up with junk in two or more scans, it'll appear here so you can keep an eye on it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct RepeatOffenderRow: View {
    let offender: RepeatOffender
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: offender.dominantCategory.symbol)
                .foregroundStyle(offender.dominantCategory.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(offender.displayPath)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Text("Seen in \(offender.appearances) scans")
                    Text("·")
                    Text("last \(offender.lastSeenAt.formatted(.relative(presentation: .named)))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            growthChip

            Text(ByteFormatting.memory(offender.latestSizeBytes))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 76, alignment: .trailing)

            Button { onReveal() } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var growthChip: some View {
        if offender.growthBytes != 0 {
            let up = offender.growthBytes > 0
            HStack(spacing: 3) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                Text(ByteFormatting.memory(UInt64(abs(offender.growthBytes))))
            }
            .font(.caption2.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(up ? .orange : .green)
            .help(up ? "Grown since first seen" : "Shrunk since first seen")
        }
    }
}

private extension RepeatOffender {
    /// Re-expands the `~`-abbreviated display path for Finder reveal.
    var displayPathExpanded: String {
        guard displayPath.hasPrefix("~") else { return displayPath }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + displayPath.dropFirst(1)
    }
}
