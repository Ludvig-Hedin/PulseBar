import Foundation

/// Resource envelope for a scan run. Replaces the hardcoded constants that used
/// to live on `CategoryScanner` so caps/deadlines can differ per tier
/// (Quick vs Deep) and, later, be user-tunable.
///
/// Everything here bounds work: a category scan stops when it hits the file cap
/// or its per-category deadline, and the whole run stops at the overall deadline.
struct ScanBudget: Equatable {
    /// Wall-clock ceiling for a single category before it reports `.timeout`.
    var perCategoryDeadlineSeconds: TimeInterval
    /// Wall-clock ceiling for the entire scan run. A pathological category can't
    /// hang everything else past this.
    var overallDeadlineSeconds: TimeInterval
    /// File cap per category root (passed into `FileEnumerator`).
    var maxFilesPerCategory: Int
    /// Minimum size for the Large Files heuristic.
    var largeFileMinBytes: UInt64
    /// Cap on the number of large files retained.
    var largeFileMaxItems: Int
    /// How many categories may scan at once inside the `ScanEngine` task group.
    var maxConcurrentCategories: Int

    private static var recommendedConcurrency: Int {
        // Leave a couple of cores for the main thread + system; IO-bound work
        // doesn't benefit from oversubscription.
        max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 2))
    }

    static func forTier(_ tier: ScanTier) -> ScanBudget {
        switch tier {
        case .quick:
            return ScanBudget(perCategoryDeadlineSeconds: 30,
                              overallDeadlineSeconds: 120,
                              maxFilesPerCategory: 10_000,
                              largeFileMinBytes: 100 * 1_024 * 1_024,
                              largeFileMaxItems: 200,
                              maxConcurrentCategories: recommendedConcurrency)
        case .deep:
            return ScanBudget(perCategoryDeadlineSeconds: 90,
                              overallDeadlineSeconds: 360,
                              maxFilesPerCategory: 40_000,
                              largeFileMinBytes: 100 * 1_024 * 1_024,
                              largeFileMaxItems: 500,
                              maxConcurrentCategories: recommendedConcurrency)
        case .ultra:
            // Ultra uses the read-only inventory engine, not the category path.
            // A budget is still returned so callers have a sane default.
            return ScanBudget(perCategoryDeadlineSeconds: 120,
                              overallDeadlineSeconds: 600,
                              maxFilesPerCategory: 40_000,
                              largeFileMinBytes: 100 * 1_024 * 1_024,
                              largeFileMaxItems: 500,
                              maxConcurrentCategories: recommendedConcurrency)
        }
    }

    /// Preserves the historical 30s / 10k behaviour for one-off single-category
    /// rescans that don't specify a tier.
    static var `default`: ScanBudget { .forTier(.quick) }
}
