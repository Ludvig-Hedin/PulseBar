import SwiftUI

/// Compact progress panel surfaced while a scan is in flight. Visible regardless
/// of which sub-view the user is on so they can always see (and cancel) work
/// in progress.
struct LiveScanPanel: View {
    @EnvironmentObject private var storageVM: StorageViewModel

    var body: some View {
        if let progress = storageVM.state.scanProgress {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning…")
                        .font(.callout.weight(.semibold))
                    if let current = progress.currentCategory {
                        Text("· \(current.title)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(progress.aggregateItems) items · \(ByteFormatting.memory(progress.aggregateBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button("Cancel", role: .destructive) {
                        storageVM.cancelScan()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                ProgressView(value: progress.fractionDone)
                    .progressViewStyle(.linear)
            }
            .padding(14)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
