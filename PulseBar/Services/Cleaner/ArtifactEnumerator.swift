import Foundation

/// Directory-oriented walker for the developer-artifact finder (Deep Scan).
///
/// Unlike `FileEnumerator` (which walks files and skips directories), this looks
/// for whole marker directories — `node_modules`, `build`, `target`, `.venv`, …
/// — records each as a single directory-level `CleanableItem`, and **prunes**
/// (does not descend into) a marker once matched. That keeps counts sane and the
/// walk fast even across a large home folder.
///
/// Safety: reads are gated by `PathAllowlist.isArtifactScanAllowed`; the matched
/// marker path is additionally validated by `PathAllowlist.isArtifactDeleteAllowed`
/// before it's reported as a cleanable item.
enum ArtifactEnumerator {
    struct Result {
        var items: [CleanableItem]
        var totalSizeBytes: UInt64
        var truncated: Bool
        var errors: [ScanError]
    }

    static func enumerate(roots: [URL],
                          budget: ScanBudget,
                          deadline: Date,
                          cancellation: () -> Bool,
                          progress: ((UInt64, Int) -> Void)? = nil) -> Result {
        var items: [CleanableItem] = []
        var total: UInt64 = 0
        var truncated = false
        var errors: [ScanError] = []
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]

        for root in roots {
            if cancellation() { break }
            guard PathAllowlist.isArtifactScanAllowed(root),
                  fm.fileExists(atPath: root.path) else { continue }

            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                // Do NOT skip hidden files — markers like `.venv`/`.next`/`.gradle`
                // are hidden. Cost is bounded by pruning + the deadline.
                options: [],
                errorHandler: { url, error in
                    let nsError = error as NSError
                    if nsError.domain == NSPOSIXErrorDomain && nsError.code == EACCES {
                        errors.append(ScanError(path: url.path, reason: .permissionDenied))
                    }
                    return true
                }
            ) else { continue }

            var lastProgressEmit = Date.distantPast

            for case let url as URL in enumerator {
                if cancellation() {
                    truncated = true
                    break
                }
                if Date() > deadline {
                    errors.append(ScanError(path: root.path, reason: .timeout))
                    truncated = true
                    break
                }
                if items.count >= budget.largeFileMaxItems {
                    truncated = true
                    break
                }

                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                guard values?.isDirectory == true else { continue }

                let name = url.lastPathComponent

                // Never descend into perf-skip dirs (Library, .git, Applications…).
                if Locations.artifactTraversalSkips.contains(name) {
                    enumerator.skipDescendants()
                    continue
                }

                // Off-limits subtree (protected user dir, symlink escape, etc.).
                guard PathAllowlist.isArtifactScanAllowed(url) else {
                    enumerator.skipDescendants()
                    continue
                }

                guard isArtifactMarker(url) else { continue }

                // Matched a marker — never descend into it, and only report it if
                // the delete gate would accept it.
                enumerator.skipDescendants()
                guard PathAllowlist.isArtifactDeleteAllowed(url) else { continue }

                let measured = measure(url, budget: budget, deadline: deadline, cancellation: cancellation)
                guard measured.bytes > 0 else { continue }

                items.append(CleanableItem(
                    url: url,
                    sizeBytes: measured.bytes,
                    modifiedAt: measured.newestModified,
                    isDirectory: true,
                    category: .devArtifacts
                ))
                total &+= measured.bytes

                let now = Date()
                if now.timeIntervalSince(lastProgressEmit) > 0.1 {
                    progress?(total, items.count)
                    lastProgressEmit = now
                }
            }
        }

        // Largest first — most impactful project junk at the top.
        items.sort { $0.sizeBytes > $1.sizeBytes }
        progress?(total, items.count)
        return Result(items: items, totalSizeBytes: total, truncated: truncated, errors: errors)
    }

    // MARK: - Marker matching

    /// True if `dir` is an artifact marker. Unconditional markers match anywhere;
    /// project-scoped markers (build/dist/target/venv/.gradle) match only when a
    /// sibling project manifest proves the parent is a real project.
    private static func isArtifactMarker(_ dir: URL) -> Bool {
        let name = dir.lastPathComponent
        if Locations.unconditionalArtifactMarkers.contains(name) { return true }
        guard Locations.projectScopedArtifactMarkers.contains(name) else { return false }
        return parentLooksLikeProject(dir)
    }

    private static func parentLooksLikeProject(_ dir: URL) -> Bool {
        let parent = dir.deletingLastPathComponent()
        let fm = FileManager.default
        for manifest in Locations.projectManifests {
            if fm.fileExists(atPath: parent.appendingPathComponent(manifest).path) {
                return true
            }
        }
        return false
    }

    // MARK: - Size measurement

    /// Recursively sums allocated size of a marker directory and tracks the
    /// newest child modification date (so abandoned projects sort old). Bounded
    /// by the per-category file cap and the overall deadline.
    private static func measure(_ dir: URL,
                                budget: ScanBudget,
                                deadline: Date,
                                cancellation: () -> Bool) -> (bytes: UInt64, newestModified: Date) {
        var bytes: UInt64 = 0
        var newest: Date = .distantPast
        var visited = 0
        let keys: [URLResourceKey] = [
            .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey, .isRegularFileKey,
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            let dirModified = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (0, dirModified)
        }

        for case let url as URL in enumerator {
            if cancellation() || Date() > deadline { break }
            visited += 1
            if visited > budget.maxFilesPerCategory { break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let size = UInt64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            bytes &+= size
            if let modified = values.contentModificationDate, modified > newest {
                newest = modified
            }
        }

        if newest == .distantPast {
            newest = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return (bytes, newest)
    }
}
