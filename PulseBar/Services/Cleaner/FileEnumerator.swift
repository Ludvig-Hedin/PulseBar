import Foundation

/// Walks a directory tree, summing `totalFileAllocatedSizeKey` per file and
/// yielding `CleanableItem`s along the way.
///
/// Hard caps:
/// - `maxFiles`: bail when this many candidates have been seen.
/// - `deadline`: bail when wall-clock time exceeds this.
/// - `cancellation`: cheap closure checked at the start of every loop iteration.
enum FileEnumerator {
    struct Result {
        var items: [CleanableItem]
        var totalSizeBytes: UInt64
        var truncated: Bool
        var errors: [ScanError]
    }

    /// Recursively enumerates `root`. Returns aggregate results; on permission denial,
    /// records a `ScanError` and continues.
    static func enumerate(root: URL,
                          category: StorageCategory,
                          maxFiles: Int = 10_000,
                          minSizeBytes: UInt64 = 0,
                          deadline: Date,
                          cancellation: () -> Bool,
                          progress: ((UInt64, Int) -> Void)? = nil) -> Result {
        var items: [CleanableItem] = []
        var totalBytes: UInt64 = 0
        var truncated = false
        var errors: [ScanError] = []

        let keys: [URLResourceKey] = [
            .totalFileAllocatedSizeKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ]

        guard PathAllowlist.isScanAllowed(root) else {
            // Allowlist refusal is silent — scanners shouldn't surface "scanned dir
            // forbidden" to users.
            return Result(items: [], totalSizeBytes: 0, truncated: false, errors: [])
        }

        guard FileManager.default.fileExists(atPath: root.path) else {
            return Result(items: [], totalSizeBytes: 0, truncated: false, errors: [])
        }

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                let nsError = error as NSError
                if nsError.domain == NSPOSIXErrorDomain && nsError.code == EACCES {
                    errors.append(ScanError(path: url.path, reason: .permissionDenied))
                } else {
                    errors.append(ScanError(path: url.path, reason: .ioError(error.localizedDescription)))
                }
                return true // keep walking; one denied subdir shouldn't abort the whole scan
            }
        ) else {
            return Result(items: [], totalSizeBytes: 0, truncated: false, errors: errors)
        }

        var lastProgressEmit = Date.distantPast

        for case let url as URL in enumerator {
            if cancellation() {
                errors.append(ScanError(path: root.path, reason: .cancelled))
                return Result(items: items, totalSizeBytes: totalBytes, truncated: true, errors: errors)
            }
            if Date() > deadline {
                errors.append(ScanError(path: root.path, reason: .timeout))
                truncated = true
                break
            }
            if items.count >= maxFiles {
                truncated = true
                break
            }

            guard PathAllowlist.isScanAllowed(url) else { continue }

            let values = try? url.resourceValues(forKeys: Set(keys))
            // Symlinks are skipped — `resolvingSymlinksInPath` in `PathAllowlist.isScanAllowed`
            // already enforces target-side rules; we don't want double-counting if both
            // link and target are in scope.
            if values?.isSymbolicLink == true { continue }
            let isDir = values?.isDirectory ?? false
            if isDir { continue }

            let size = UInt64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            guard size > 0 else { continue }
            if size < minSizeBytes { continue }

            let modified = values?.contentModificationDate ?? .distantPast
            items.append(CleanableItem(
                url: url,
                sizeBytes: size,
                modifiedAt: modified,
                isDirectory: false,
                category: category
            ))
            totalBytes &+= size

            // Coalesce progress callbacks at ~10 Hz.
            let now = Date()
            if now.timeIntervalSince(lastProgressEmit) > 0.1 {
                progress?(totalBytes, items.count)
                lastProgressEmit = now
            }
        }

        progress?(totalBytes, items.count)
        return Result(items: items, totalSizeBytes: totalBytes, truncated: truncated, errors: errors)
    }
}
