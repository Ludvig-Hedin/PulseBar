import Foundation

/// The three scan depths surfaced in the Storage tab.
///
/// The tier is orthogonal to `StorageCategory`: the category enum stays the
/// source of truth for *what* is scanned and deleted, while the tier decides
/// *which set of categories*, *how big a budget*, and *which execution path*
/// (category scan vs. whole-disk inventory) a run uses.
enum ScanTier: String, CaseIterable, Identifiable, Codable, Hashable {
    /// Curated cache/log categories. Fast, safe, auto-clean eligible.
    case quick
    /// Quick categories plus Large Files and developer artifacts, bigger budget.
    case deep
    /// Read-only inventory of every file on the boot volume. Requires Full Disk
    /// Access. Never feeds the deletion flow directly.
    case ultra

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: return "Quick Scan"
        case .deep:  return "Deep Scan"
        case .ultra: return "Ultra Scan"
        }
    }

    var subtitle: String {
        switch self {
        case .quick: return "Curated caches, logs, and dev-tool junk"
        case .deep:  return "Everything in Quick, plus large files and project artifacts"
        case .ultra: return "Map every file on your disk (read-only)"
        }
    }

    var symbol: String {
        switch self {
        case .quick: return "bolt"
        case .deep:  return "magnifyingglass"
        case .ultra: return "globe"
        }
    }

    /// Categories scanned for this tier. Ultra returns `[]` — it uses the
    /// inventory engine instead of the category path.
    var categories: [StorageCategory] {
        switch self {
        case .quick:
            return StorageCategory.allCases.filter(\.isInSmartScan)
        case .deep:
            return StorageCategory.allCases.filter(\.isInSmartScan) + [.largeFiles]
        case .ultra:
            return []
        }
    }

    /// Ultra reads the whole volume and needs Full Disk Access to see everything.
    var requiresFullDiskAccess: Bool { self == .ultra }

    /// True when this tier runs the read-only `DiskInventoryEngine` rather than
    /// the per-category scanners.
    var usesInventoryPath: Bool { self == .ultra }

    var budget: ScanBudget { .forTier(self) }
}
