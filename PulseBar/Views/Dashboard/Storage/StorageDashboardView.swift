import SwiftUI

/// Storage tab's Dashboard sub-view: hero gauge + stats grid + scan controls + live results.
struct StorageDashboardView: View {
    @EnvironmentObject private var storageVM: StorageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            heroSection

            statsGrid

            if let usage = storageVM.diskUsage {
                breakdownCard(usage)
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        HStack(alignment: .center, spacing: 28) {
            if let usage = storageVM.diskUsage {
                StorageGauge(
                    usedRatio: usage.usedRatio,
                    centerLabel: "\(Int(usage.usedPercent))%",
                    centerSublabel: "Used"
                )
            } else {
                ProgressView()
                    .frame(width: 200, height: 200)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("Macintosh HD")
                    .font(.title2.weight(.semibold))
                if let usage = storageVM.diskUsage {
                    Text("\(usage.freeFormatted) free of \(usage.totalFormatted)")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        storageVM.startSmartScan()
                    } label: {
                        Label(storageVM.isScanRunning ? "Scanning…" : "Smart Scan", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(storageVM.isScanRunning || storageVM.isAutoCleaning)

                    Button {
                        storageVM.startScan(tier: .deep)
                    } label: {
                        Label("Deep Scan", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .disabled(storageVM.isScanRunning || storageVM.isAutoCleaning)
                    .help("Also scan large files and project artifacts (node_modules, build, target, .venv) across your home folder.")

                    Button {
                        storageVM.startUltraScan()
                    } label: {
                        Label("Ultra Scan", systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                    .disabled(storageVM.isScanRunning || storageVM.isAutoCleaning || storageVM.isInventoryRunning)
                    .help("Map every file on your whole disk (read-only) to find where space went.")

                    Button {
                        storageVM.requestQuickClean()
                    } label: {
                        Label(storageVM.isAutoCleaning ? "Cleaning…" : "Quick Clean",
                              systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .disabled(storageVM.isScanRunning || storageVM.isAutoCleaning)
                    .help("Scan and move safe junk (caches, logs) straight to Trash — reversible.")

                    if storageVM.isScanRunning {
                        Button("Cancel", role: .destructive) {
                            storageVM.cancelScan()
                        }
                        .buttonStyle(.bordered)
                    }

                    // CTA: only show when we have actionable junk from a completed scan
                    if storageVM.state.totalJunkBytes > 0 && !storageVM.isScanRunning {
                        Button {
                            storageVM.quickSelectAllAndShowFiles()
                        } label: {
                            Label("Review & Clean \(ByteFormatting.gigabytes(storageVM.state.totalJunkBytes))",
                                  systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
            let usage = storageVM.diskUsage
            statTile(title: "Total",
                     icon: "internaldrive",
                     value: usage?.totalFormatted ?? "—",
                     subtitle: "Volume capacity")
            statTile(title: "Free",
                     icon: "checkmark.circle",
                     value: usage?.freeFormatted ?? "—",
                     subtitle: "Available now")
            statTile(title: "Junk Found",
                     icon: "trash",
                     value: ByteFormatting.memory(storageVM.state.totalJunkBytes),
                     subtitle: lastScanSubtitle,
                     valueTint: storageVM.state.totalJunkBytes > 0 ? .orange : .primary)
            statTile(title: "Purgeable",
                     icon: "sparkles",
                     value: usage?.purgeableFormatted ?? "—",
                     subtitle: "Reclaimable by macOS")
        }
    }

    private func statTile(title: String, icon: String, value: String,
                          subtitle: String, valueTint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(valueTint)
                .monospacedDigit()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var lastScanSubtitle: String {
        if storageVM.isScanRunning { return "Scanning…" }
        if let date = storageVM.state.lastScanAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Updated \(formatter.localizedString(for: date, relativeTo: .now))"
        }
        return "Run Smart Scan to find junk"
    }

    // MARK: - Breakdown card

    private func breakdownCard(_ usage: DiskUsage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Breakdown")
                .font(.title3.weight(.semibold))
            StorageUsageChart(usage: usage)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
