import Foundation

/// Result of scanning a single category.
struct CategoryResult: Identifiable, Equatable, Hashable {
    let category: StorageCategory
    let items: [CleanableItem]
    let totalSizeBytes: UInt64
    let scannedAt: Date
    /// True if the scan hit a file cap or deadline before enumerating everything.
    let truncated: Bool
    let errors: [ScanError]

    var id: StorageCategory { category }
    var itemCount: Int { items.count }
    var totalFormatted: String { ByteFormatting.memory(totalSizeBytes) }

    /// Fresh enough to use without rescanning. Five-minute TTL matches `ScanEngine`'s cache.
    var isFresh: Bool {
        Date().timeIntervalSince(scannedAt) < 300
    }
}

/// Per-path failure encountered during a scan. Surfaced in the UI so users
/// understand why an expected category came back small.
struct ScanError: Hashable, Equatable {
    let path: String
    let reason: Reason

    enum Reason: Hashable {
        case permissionDenied
        case ioError(String)
        case timeout
        case cancelled
    }

    var displayMessage: String {
        switch reason {
        case .permissionDenied:    return "Permission denied — Full Disk Access required"
        case .ioError(let detail): return "I/O error: \(detail)"
        case .timeout:             return "Timed out before finishing"
        case .cancelled:           return "Cancelled"
        }
    }
}
