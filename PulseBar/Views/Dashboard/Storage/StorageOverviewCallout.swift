import SwiftUI

/// Slim callout shown under the Overview grid summarising the last storage scan.
/// Two states:
/// - **Fresh scan**: "Junk found: X GB" with "View details" jumping to Storage.
/// - **No scan yet / stale**: "Scan to find junk" CTA.
struct StorageOverviewCallout: View {
    @EnvironmentObject private var storageVM: StorageViewModel
    let onShowStorage: () -> Void

    var body: some View {
        let summary = storageVM.junkSummary
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: summary.isFresh ? "sparkles" : "wand.and.stars")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.isFresh ? "Junk found: \(summary.totalFormatted)" : "Scan to find junk")
                    .font(.body.weight(.semibold))
                Text(subtitle(summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                // Land on the actionable Categories sub-view rather than the hero gauge
                // so the user immediately sees scanned categories streaming in.
                storageVM.subview = .categories
                if !storageVM.isScanRunning && !summary.isFresh {
                    storageVM.startSmartScan()
                }
                onShowStorage()
            } label: {
                Text(summary.isFresh ? "View details" : "Scan & open Storage")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.16))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(summary.isFresh ? "Jump to the Storage tab" : "Start a Smart Scan and open the Storage tab")
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func subtitle(_ summary: StorageViewModel.JunkSummary) -> String {
        if storageVM.isScanRunning {
            return "Scanning…"
        }
        if summary.isFresh, let date = summary.lastScanAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Last scan \(formatter.localizedString(for: date, relativeTo: .now))"
        }
        return "Smart Scan checks caches, logs, Trash, and dev artifacts."
    }
}
