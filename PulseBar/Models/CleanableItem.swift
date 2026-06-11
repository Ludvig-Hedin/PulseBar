import Foundation

/// A single file or directory eligible for cleanup. Selection state is held
/// elsewhere (in `StorageViewModel.selectedItems`) so a re-scan keeps the user's
/// picks intact.
struct CleanableItem: Identifiable, Hashable, Equatable {
    let url: URL
    let sizeBytes: UInt64
    let modifiedAt: Date
    let isDirectory: Bool
    let category: StorageCategory

    var id: URL { url }

    var displayName: String { url.lastPathComponent }
    var parentDirectory: String { url.deletingLastPathComponent().path }
    var sizeFormatted: String { ByteFormatting.memory(sizeBytes) }
}
