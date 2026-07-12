import SwiftUI
import AppKit

/// Storage tab root. Hosts the FDA banner, sub-view picker, sticky clean bar,
/// and the modal cleanup confirmation.
struct StorageSection: View {
    @EnvironmentObject private var storageVM: StorageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if storageVM.state.fullDiskAccessGranted == false {
                FullDiskAccessBanner(
                    onOpenSettings: { storageVM.openFullDiskAccessSettings() },
                    onRecheck: { storageVM.recheckFullDiskAccess() }
                )
            }

            if let summary = storageVM.lastCleanupSummary {
                cleanupSummaryCard(summary)
            }

            if let outcome = storageVM.lastAutoCleanOutcome,
               let banner = autoCleanBanner(for: outcome) {
                banner
            }

            // Always-visible scan progress so the user sees (and can cancel) work
            // regardless of which Storage sub-view they're on.
            LiveScanPanel()
                .environmentObject(storageVM)

            subviewPicker

            Group {
                switch storageVM.subview {
                case .dashboard:
                    StorageDashboardView()
                        .environmentObject(storageVM)
                case .files:
                    AllFilesView()
                        .environmentObject(storageVM)
                case .categories:
                    StorageCategoriesView()
                        .environmentObject(storageVM)
                case .diskMap:
                    DiskInventoryView()
                        .environmentObject(storageVM)
                case .settings:
                    StorageSettingsView()
                        .environmentObject(storageVM)
                }
            }

            if storageVM.selectedTotalCount > 0 || storageVM.isCleaning {
                StickyCleanBar(
                    selectedCount: storageVM.selectedTotalCount,
                    selectedBytes: storageVM.selectedTotalBytes,
                    isCleaning: storageVM.isCleaning,
                    onClean: { storageVM.requestCleanup() },
                    onClear: { storageVM.clearSelection() }
                )
            }
        }
        .sheet(isPresented: $storageVM.showCleanConfirmation) {
            CleanConfirmationDialog(
                items: storageVM.selectedCleanables,
                onCancel: { storageVM.cancelCleanupConfirmation() },
                onClean: { mode in storageVM.performCleanup(mode: mode) }
            )
        }
        .sheet(isPresented: $storageVM.showDockerPruneConfirmation) {
            DockerPruneConfirmationDialog(
                reclaimableBytes: storageVM.dockerReclaimableBytes,
                onCancel: { storageVM.cancelDockerPruneConfirmation() },
                onPrune: { storageVM.performDockerPrune() }
            )
        }
        .sheet(isPresented: $storageVM.showAutoCleanConsent) {
            AutoCleanConsentDialog(
                onCancel: { storageVM.cancelAutoCleanConsent() },
                onAccept: { storageVM.confirmAutoCleanConsent() }
            )
        }
        .sheet(isPresented: $storageVM.showAIKeyEntry) {
            AIKeyEntryDialog(
                onCancel: { storageVM.cancelAIKeyEntry() },
                onSave: { storageVM.saveAIKeyAndSummarize($0) }
            )
        }
    }

    /// Banner for the non-success auto-clean outcomes. Success reuses the green
    /// `cleanupSummaryCard`; here we cover the circuit-breaker pause and the
    /// nothing-to-do case.
    private func autoCleanBanner(for outcome: AutoCleanCoordinator.Outcome) -> AnyView? {
        switch outcome.result {
        case .abortedTooMuch:
            return AnyView(noticeCard(
                icon: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "Auto-clean paused",
                detail: "Found \(ByteFormatting.memory(outcome.bytesFound)) of junk — more than expected. Review it manually before cleaning.",
                onDismiss: { storageVM.lastAutoCleanOutcome = nil }
            ))
        case .nothingFound:
            return AnyView(noticeCard(
                icon: "checkmark.circle.fill",
                tint: .secondary,
                title: "Nothing to clean",
                detail: "Quick Clean found no safe junk to remove.",
                onDismiss: { storageVM.lastAutoCleanOutcome = nil }
            ))
        case .cleaned, .disabled, .alreadyRunning:
            return nil
        }
    }

    private func noticeCard(icon: String, tint: Color, title: String, detail: String,
                            onDismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(14)
        .background(tint == .secondary ? Color.secondary.opacity(0.08) : tint.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder((tint == .secondary ? Color.secondary : tint).opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var subviewPicker: some View {
        Picker("View", selection: $storageVM.subview) {
            ForEach(StorageViewModel.Subview.allCases) { sub in
                Label(sub.rawValue, systemImage: sub.symbol).tag(sub)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 600)
    }

    private func cleanupSummaryCard(_ summary: StorageViewModel.CleanupSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.kind == .docker ? "Docker reclaimed \(summary.totalFormatted)" : "Reclaimed \(summary.totalFormatted)")
                    .font(.body.weight(.semibold))
                Text(summaryDetail(summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Trash-mode cleanups are recoverable — make finding them one click away.
            if summary.kind == .files && summary.succeeded > 0 {
                Button {
                    let trash = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".Trash", isDirectory: true)
                    NSWorkspace.shared.open(trash)
                } label: {
                    Label("Show in Trash", systemImage: "trash")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
            Button {
                storageVM.lastCleanupSummary = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(14)
        .background(Color.green.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.green.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: summary.completedAt) {
            // Auto-dismiss the toast after 8s so it doesn't haunt the screen between
            // unrelated scans. Cancelled if a new summary lands (different completedAt).
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if storageVM.lastCleanupSummary?.completedAt == summary.completedAt {
                storageVM.lastCleanupSummary = nil
            }
        }
    }

    private func summaryDetail(_ summary: StorageViewModel.CleanupSummary) -> String {
        switch summary.kind {
        case .files:
            return "\(summary.succeeded) deleted · \(summary.failed) failed · \(summary.refused) refused"
        case .docker:
            return "\(summary.succeeded) prune completed · \(summary.failed) failed · \(summary.refused) refused"
        }
    }

}

/// One-time consent shown before the first unattended auto-clean. Spells out
/// exactly what "Quick Clean" does so the opt-in is informed.
private struct AutoCleanConsentDialog: View {
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Turn on Quick Clean?")
                        .font(.title2.weight(.semibold))
                    Text("One click scans for safe junk and moves it straight to the Trash — no per-file review.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                consentRow(icon: "arrow.uturn.backward", text: "Everything goes to the Trash, so you can restore it. Nothing is deleted permanently.")
                consentRow(icon: "shield.lefthalf.filled", text: "Only rebuildable caches and logs (system, app, Xcode, Homebrew, npm). Never your documents or large files.")
                consentRow(icon: "gauge.with.dots.needle.67percent", text: "If a run finds far more than expected, it pauses and asks you to review instead.")
            }
            .padding(14)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button {
                    onAccept()
                } label: {
                    Label("Turn On & Clean", systemImage: "sparkles")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func consentRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 20)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct DockerPruneConfirmationDialog: View {
    let reclaimableBytes: UInt64
    let onCancel: () -> Void
    let onPrune: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "cube.box")
                    .font(.title)
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prune Docker \(ByteFormatting.memory(reclaimableBytes))?")
                        .font(.title2.weight(.semibold))
                    Text("Removes stopped containers, unused networks, dangling images, and build cache. Docker volumes are not removed.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button {
                    onPrune()
                } label: {
                    Text("Prune Docker")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
