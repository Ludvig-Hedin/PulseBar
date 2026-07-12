import Foundation

/// Turns raw scan results, disk usage, and history into a short, ranked list of
/// plain-language insights. Pure and deterministic — no network, no LLM — so it
/// always works and costs nothing. The optional `AISummaryService` layers a
/// natural-language interpretation on top of these.
enum StorageInsightsEngine {
    /// Thresholds tuned so we only surface things worth a sentence.
    private static let reclaimableFloor: UInt64 = 500 * 1_024 * 1_024      // 500 MB
    private static let bigFootprintFloor: UInt64 = 1 * 1_024 * 1_024 * 1_024 // 1 GB
    private static let staleDays: Double = 90

    static func generate(results: [StorageCategory: CategoryResult],
                         disk: DiskUsage?,
                         offenders: [RepeatOffender],
                         junkTrend: [TrendPoint]) -> [StorageInsight] {
        var insights: [StorageInsight] = []

        // 1. Disk pressure — most urgent.
        if let disk, disk.totalBytes > 0 {
            let freeRatio = Double(disk.freeBytes) / Double(disk.totalBytes)
            if freeRatio < 0.10 {
                insights.append(StorageInsight(
                    id: "disk-pressure",
                    kind: .diskPressure,
                    title: "Your disk is almost full",
                    detail: "Only \(disk.freeFormatted) free of \(disk.totalFormatted) (\(Int(freeRatio * 100))%). Cleaning junk now will keep things fast.",
                    sizeBytes: disk.freeBytes,
                    actionHint: "Run Quick Clean"
                ))
            }
        }

        // 2. Reclaimable cache/log categories, largest first.
        let reclaimable = results.values
            .filter { $0.isFresh && $0.category.isNormallyCleanable && $0.category != .devArtifacts }
            .filter { $0.totalSizeBytes >= reclaimableFloor }
            .sorted { $0.totalSizeBytes > $1.totalSizeBytes }
        for result in reclaimable.prefix(3) {
            insights.append(StorageInsight(
                id: "reclaim-\(result.category.rawValue)",
                kind: .reclaimable,
                title: "\(ByteFormatting.memory(result.totalSizeBytes)) of \(result.category.title.lowercased())",
                detail: reclaimableDetail(for: result.category, bytes: result.totalSizeBytes),
                sizeBytes: result.totalSizeBytes,
                actionHint: "Move to Trash"
            ))
        }

        // 3. Developer artifacts — big and rebuildable, with age emphasis.
        if let devResult = results[.devArtifacts], devResult.isFresh, devResult.totalSizeBytes >= reclaimableFloor {
            let now = Date()
            let staleCutoff = now.addingTimeInterval(-staleDays * 86_400)
            let staleCount = devResult.items.filter { $0.modifiedAt < staleCutoff }.count
            let staleClause = staleCount > 0
                ? " \(staleCount) of them haven't been touched in \(Int(staleDays))+ days — likely old one-off projects."
                : ""
            insights.append(StorageInsight(
                id: "dev-artifacts",
                kind: .bigFootprint,
                title: "\(ByteFormatting.memory(devResult.totalSizeBytes)) in project build folders",
                detail: "\(devResult.itemCount) folders like node_modules, build, and .venv across your home folder.\(staleClause) They rebuild automatically when you next run the project.",
                sizeBytes: devResult.totalSizeBytes,
                actionHint: "Review project junk"
            ))
        }

        // 4. Large files (reveal-only) worth pointing at.
        if let large = results[.largeFiles], large.isFresh, large.totalSizeBytes >= bigFootprintFloor {
            insights.append(StorageInsight(
                id: "large-files",
                kind: .bigFootprint,
                title: "\(ByteFormatting.memory(large.totalSizeBytes)) in large files",
                detail: "\(large.itemCount) big files (100 MB+). These are your own files — review before removing anything.",
                sizeBytes: large.totalSizeBytes,
                actionHint: "Open Disk Map"
            ))
        }

        // 5. Repeat offenders — a folder that keeps refilling is the highest-signal
        //    "recurring junk" insight.
        if let worst = offenders.first(where: { $0.appearances >= 2 }) {
            insights.append(StorageInsight(
                id: "offender-\(worst.folderKey)",
                kind: .repeatOffender,
                title: "This folder keeps filling up",
                detail: "\(worst.displayPath) has shown junk in \(worst.appearances) scans (now \(ByteFormatting.memory(worst.latestSizeBytes))). Worth a permanent look at what writes there.",
                sizeBytes: worst.latestSizeBytes,
                actionHint: "See repeat offenders"
            ))
        }

        // 6. Trend — junk growing across scans.
        if junkTrend.count >= 2, let first = junkTrend.first, let last = junkTrend.last,
           last.bytes > first.bytes {
            let growth = last.bytes - first.bytes
            if growth >= reclaimableFloor {
                insights.append(StorageInsight(
                    id: "trend-up",
                    kind: .trend,
                    title: "Junk is trending up",
                    detail: "You've accumulated \(ByteFormatting.memory(growth)) more junk since your first saved scan. A regular Quick Clean keeps it in check.",
                    sizeBytes: growth,
                    actionHint: "See trends"
                ))
            }
        }

        // Rank by impact (size), keep disk-pressure pinned to the top.
        let (pinned, rest) = insights.stablePartition { $0.kind == .diskPressure }
        let ranked = pinned + rest.sorted { $0.sizeBytes > $1.sizeBytes }

        if ranked.isEmpty {
            return [StorageInsight(
                id: "all-clear",
                kind: .allClear,
                title: "Nothing significant to clean",
                detail: "Your latest scan didn't find meaningful junk. Run a Deep or Ultra scan to look wider.",
                sizeBytes: 0,
                actionHint: nil
            )]
        }
        return Array(ranked.prefix(6))
    }

    private static func reclaimableDetail(for category: StorageCategory, bytes: UInt64) -> String {
        switch category {
        case .systemJunk: return "System logs and temp files. Safe to clear — macOS rebuilds what it needs."
        case .userCache:  return "Per-app caches. Apps recreate these on next launch."
        case .aiApps:     return "Cached models and data from AI tools. Re-downloaded on demand."
        case .xcodeJunk:  return "Xcode DerivedData, archives, and simulator caches. Rebuilt on next build."
        case .brewCache:  return "Downloaded Homebrew bottles. Re-fetched when you reinstall."
        case .nodeCache:  return "npm/yarn/pnpm/cargo package caches. Re-fetched on next install."
        case .trash:      return "Everything in your Trash. Emptying is permanent."
        case .mailDownloads: return "Attachments Mail kept on disk. Removing them doesn't delete the emails."
        default:          return "Safe to move to Trash."
        }
    }
}

private extension Array {
    /// Splits into (elements matching predicate, the rest), preserving order.
    func stablePartition(_ predicate: (Element) -> Bool) -> ([Element], [Element]) {
        var yes: [Element] = []
        var no: [Element] = []
        for element in self {
            if predicate(element) { yes.append(element) } else { no.append(element) }
        }
        return (yes, no)
    }
}
