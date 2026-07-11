import Foundation

/// User policy for the one-click "Quick Scan + Clean" auto-clean flow.
///
/// Deliberately has **no deletion-mode field**: the coordinator always trashes
/// (reversible), so a corrupted or tampered persisted policy can never cause a
/// permanent or admin deletion. The policy only decides *what* to trash and the
/// *limits* that trip the circuit breaker.
struct AutoCleanPolicy: Codable, Equatable {
    /// Master opt-in. False until the user accepts the one-time consent dialog.
    var enabled: Bool
    /// Categories eligible for unattended trashing. Only ever cleanable cache /
    /// log / dev-artifact categories — never Large Files, Docker, Purgeable, or
    /// Trash itself.
    var categories: Set<StorageCategory>
    /// Circuit breaker: abort (don't trash) if a run would move more than this.
    var maxTotalBytesPerRun: UInt64
    /// Circuit breaker: abort if a run would trash more items than this.
    var maxItemsPerRun: Int
    /// Only trash items not modified within the last N days (0 = no age filter).
    var minItemAgeDays: Int

    /// Safe default set — cache/log categories that rebuild themselves. Excludes
    /// Mail Downloads (FDA + arguably user data) and Trash (nonsensical to
    /// force-trash items already in Trash).
    static let defaultCategories: Set<StorageCategory> = [
        .systemJunk, .userCache, .aiApps, .xcodeJunk, .brewCache, .nodeCache,
    ]

    static let `default` = AutoCleanPolicy(
        enabled: false,
        categories: defaultCategories,
        maxTotalBytesPerRun: 20 * 1_024 * 1_024 * 1_024, // 20 GB
        maxItemsPerRun: 20_000,
        minItemAgeDays: 0
    )
}
