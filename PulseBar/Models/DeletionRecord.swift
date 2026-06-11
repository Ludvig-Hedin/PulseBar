import Foundation

/// Audit entry for the in-memory "What did I just delete?" log.
/// Capped at 100 entries on `StorageState.recentDeletions`.
struct DeletionRecord: Identifiable, Hashable, Equatable {
    let id: UUID
    let url: URL
    let sizeBytes: UInt64
    let deletedAt: Date
    let category: StorageCategory
    let mode: DeletionMode
    let result: DeletionResult

    init(id: UUID = UUID(),
         url: URL,
         sizeBytes: UInt64,
         deletedAt: Date = .now,
         category: StorageCategory,
         mode: DeletionMode,
         result: DeletionResult) {
        self.id = id
        self.url = url
        self.sizeBytes = sizeBytes
        self.deletedAt = deletedAt
        self.category = category
        self.mode = mode
        self.result = result
    }

    var displayName: String { url.lastPathComponent }
    var sizeFormatted: String { ByteFormatting.memory(sizeBytes) }

    enum DeletionResult: Hashable, Equatable {
        case succeeded
        case failed(String)
        case refused(String)

        var isSuccess: Bool {
            if case .succeeded = self { return true }
            return false
        }

        var failureMessage: String? {
            switch self {
            case .succeeded:          return nil
            case .failed(let msg):    return msg
            case .refused(let msg):   return msg
            }
        }
    }
}
