import Foundation

/// Orchestrates per-category scans on a background task and yields progress
/// events through an `AsyncStream`.
///
/// Threading:
/// - Public entry points are actor-isolated, so cancellation flag mutations are race-free.
/// - The heavy work runs in `Task.detached(priority: .utility)`; it calls back into the
///   actor only to fire stream events and to read the cancellation flag.
actor ScanEngine {
    enum Event {
        case started(StorageCategory)
        case partial(category: StorageCategory, runningBytes: UInt64, runningCount: Int)
        case completed(CategoryResult)
        case failed(StorageCategory, ScanError)
        case finished
    }

    /// Default categories included in a Smart Scan.
    static var smartScanCategories: [StorageCategory] {
        StorageCategory.allCases.filter(\.isInSmartScan)
    }

    private var inFlight: Task<Void, Never>?
    /// Monotonically increasing tag. When a new scan starts the prior task's writes
    /// (still draining) are ignored because their generation is stale.
    private var generation: UInt64 = 0
    private var cachedResults: [StorageCategory: CategoryResult] = [:]
    private static let cacheTTL: TimeInterval = 300 // 5 min

    /// Starts a scan over `categories`. Cancels any prior scan first. Returns a stream
    /// the caller consumes on its own task; the stream finishes after the last
    /// `.finished` event.
    ///
    /// Categories run concurrently, bounded by `budget.maxConcurrentCategories`.
    /// Each category touches a disjoint set of static roots, so parallelism only
    /// adds IO pressure, not correctness hazards; results are still keyed by
    /// category downstream.
    func startScan(_ categories: [StorageCategory], budget: ScanBudget = .default) -> AsyncStream<Event> {
        cancelLocked()
        generation &+= 1
        let myGeneration = generation
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        let categoriesToRun = expand(categories)
        let overallDeadline = Date().addingTimeInterval(budget.overallDeadlineSeconds)
        let maxConcurrent = max(1, budget.maxConcurrentCategories)

        inFlight = Task.detached(priority: .utility) { [weak self] in
            guard let self else {
                continuation.finish()
                return
            }

            // `Task.isCancelled` propagates from this detached task, so the actor's
            // `cancelLocked()` makes every child scanner observe cancellation. The
            // overall deadline is a second, time-based stop condition.
            let stop: @Sendable () -> Bool = { Task.isCancelled || Date() > overallDeadline }

            await withTaskGroup(of: (StorageCategory, CategoryResult?).self) { group in
                var iterator = categoriesToRun.makeIterator()
                var inFlightCount = 0

                @Sendable func scanChild(_ category: StorageCategory) -> (StorageCategory, CategoryResult?) {
                    if stop() { return (category, nil) }
                    let deadline = min(Date().addingTimeInterval(budget.perCategoryDeadlineSeconds), overallDeadline)
                    let result = CategoryScanner.scan(
                        category: category,
                        budget: budget,
                        deadline: deadline,
                        cancellation: stop,
                        progress: { bytes, count in
                            continuation.yield(.partial(category: category, runningBytes: bytes, runningCount: count))
                        }
                    )
                    return (category, result)
                }

                func startNext() -> Bool {
                    guard let category = iterator.next() else { return false }
                    continuation.yield(.started(category))
                    group.addTask(priority: .utility) { scanChild(category) }
                    inFlightCount += 1
                    return true
                }

                while inFlightCount < maxConcurrent, startNext() {}

                while inFlightCount > 0 {
                    guard let (category, result) = await group.next() else { break }
                    inFlightCount -= 1
                    if let result {
                        // Discard writes from a superseded scan so a slow late finisher
                        // cannot overwrite the newer scan's fresh results.
                        let accepted = await self.storeIfCurrent(result: result, generation: myGeneration)
                        if accepted { continuation.yield(.completed(result)) }
                    } else {
                        continuation.yield(.failed(category, ScanError(path: "", reason: .cancelled)))
                    }
                    if !stop() { _ = startNext() }
                }
            }

            continuation.yield(.finished)
            continuation.finish()
            await self.clearInFlightIfCurrent(generation: myGeneration)
        }

        return stream
    }

    /// Cancels the currently-running scan, if any. Idempotent.
    func cancel() {
        cancelLocked()
    }

    /// Snapshot of cached results (whatever survived TTL). Used to seed the UI on first
    /// open without forcing a rescan.
    func currentResults() -> [StorageCategory: CategoryResult] {
        cachedResults.filter { Date().timeIntervalSince($0.value.scannedAt) < Self.cacheTTL }
    }

    // MARK: - Private helpers

    private func cancelLocked() {
        inFlight?.cancel()
        inFlight = nil
    }

    private func storeIfCurrent(result: CategoryResult, generation: UInt64) -> Bool {
        guard generation == self.generation else { return false }
        cachedResults[result.category] = result
        return true
    }

    private func clearInFlightIfCurrent(generation: UInt64) {
        guard generation == self.generation else { return }
        inFlight = nil
    }

    /// Expands `.smartScan` into its constituent categories. Other entries pass through.
    private func expand(_ categories: [StorageCategory]) -> [StorageCategory] {
        var seen = Set<StorageCategory>()
        var out: [StorageCategory] = []
        for cat in categories {
            if cat == .smartScan {
                for sub in Self.smartScanCategories where !seen.contains(sub) {
                    out.append(sub)
                    seen.insert(sub)
                }
            } else if !seen.contains(cat) {
                out.append(cat)
                seen.insert(cat)
            }
        }
        return out
    }
}
