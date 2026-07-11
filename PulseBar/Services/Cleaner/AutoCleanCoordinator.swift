import Foundation

/// The single place in the app that composes scan → delete without a human in
/// the loop. Isolated in one small file so the safety reviewer can audit the
/// entire unattended-deletion surface at once.
///
/// Hard safety rules (enforced here, not configurable):
/// - Deletion mode is a local `.trash` constant, never read from the policy.
/// - A circuit breaker aborts the whole run (deletes nothing) if the scan finds
///   more than the policy's byte/item ceiling.
/// - Only categories the normal cleaner considers cleanable are ever touched.
@MainActor
final class AutoCleanCoordinator {
    struct Outcome: Equatable {
        enum Result: Equatable {
            case cleaned          // items were trashed
            case nothingFound     // scan found no eligible junk
            case abortedTooMuch   // circuit breaker tripped — nothing deleted
            case disabled         // policy not enabled
            case alreadyRunning
        }
        let result: Result
        let bytesReclaimed: UInt64
        let itemsTrashed: Int
        let bytesFound: UInt64
        let itemsFound: Int
        let at: Date
    }

    private let service: StorageService
    private var isRunning = false

    init(service: StorageService) {
        self.service = service
    }

    /// Runs a Quick-tier scan and trashes the eligible results, subject to the
    /// policy's category filter, age filter, and circuit-breaker ceilings.
    func run(policy: AutoCleanPolicy) async -> Outcome {
        guard policy.enabled else {
            return Outcome(result: .disabled, bytesReclaimed: 0, itemsTrashed: 0,
                           bytesFound: 0, itemsFound: 0, at: .now)
        }
        guard !isRunning else {
            return Outcome(result: .alreadyRunning, bytesReclaimed: 0, itemsTrashed: 0,
                           bytesFound: 0, itemsFound: 0, at: .now)
        }
        isRunning = true
        defer { isRunning = false }

        // 1. Scan Quick tier to completion.
        let results = await service.runQuickScanToCompletion()

        // 2. Build the eligible delete set: cleanable ∧ in policy ∧ old enough.
        let ageCutoff: Date? = policy.minItemAgeDays > 0
            ? Date().addingTimeInterval(-Double(policy.minItemAgeDays) * 86_400)
            : nil

        var candidates: [CleanableItem] = []
        for (category, result) in results {
            guard StorageViewModel.isCleanable(category),
                  policy.categories.contains(category) else { continue }
            for item in result.items {
                if let ageCutoff, item.modifiedAt > ageCutoff { continue }
                candidates.append(item)
            }
        }

        let bytesFound = candidates.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        let itemsFound = candidates.count

        // 3. Circuit breaker — abort without deleting when a run finds more than
        //    the policy expects (e.g. a tool relocated a huge cache under a
        //    scanned root).
        if bytesFound > policy.maxTotalBytesPerRun || itemsFound > policy.maxItemsPerRun {
            NotificationService.shared.postAutoCleanResult(
                title: "Auto-clean paused",
                body: "Found \(ByteFormatting.memory(bytesFound)) of junk — more than expected. Review it manually before cleaning."
            )
            return Outcome(result: .abortedTooMuch, bytesReclaimed: 0, itemsTrashed: 0,
                           bytesFound: bytesFound, itemsFound: itemsFound, at: .now)
        }

        if candidates.isEmpty {
            return Outcome(result: .nothingFound, bytesReclaimed: 0, itemsTrashed: 0,
                           bytesFound: 0, itemsFound: 0, at: .now)
        }

        // 4. Force trash mode. This constant is the load-bearing safety guarantee:
        //    the policy cannot escalate deletion beyond a reversible move to Trash.
        let mode: DeletionMode = .trash
        let records = await service.deleteSelected(items: candidates, mode: mode)

        let succeeded = records.filter { $0.result.isSuccess }
        let reclaimed = succeeded.reduce(UInt64(0)) { $0 + $1.sizeBytes }

        NotificationService.shared.postAutoCleanResult(
            title: "Auto-clean complete",
            body: "Moved \(ByteFormatting.memory(reclaimed)) to Trash (\(succeeded.count) items). You can restore anything from Trash."
        )

        return Outcome(result: .cleaned, bytesReclaimed: reclaimed, itemsTrashed: succeeded.count,
                       bytesFound: bytesFound, itemsFound: itemsFound, at: .now)
    }
}
