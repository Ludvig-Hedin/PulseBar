import Foundation

/// Builds a read-only, folder-level size map of the boot volume (Ultra Scan).
///
/// This deliberately bypasses `PathAllowlist` for READS — the whole point is to
/// see everything — but it produces only `InventoryNode`s, which have no path
/// into `CleanupService`. Visibility is total; deletion stays gated elsewhere.
///
/// Memory is bounded by folder-level aggregation: the recursive walk keeps only
/// children above `minReportBytes` and caps each folder to `maxChildrenPerNode`,
/// folding the remainder into a synthetic "(smaller items)" node. Peak retention
/// is O(retained nodes), not O(files).
actor DiskInventoryEngine {
    enum Event {
        case started
        case progress(scannedFiles: Int, scannedBytes: UInt64)
        case finished(root: InventoryNode?)
        case failed(ScanError)
    }

    private var inFlight: Task<Void, Never>?

    func inventory(root: URL = URL(fileURLWithPath: "/"), budget: InventoryBudget) -> AsyncStream<Event> {
        cancelLocked()
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)

        inFlight = Task.detached(priority: .utility) {
            continuation.yield(.started)
            let deadline = Date().addingTimeInterval(budget.overallDeadlineSeconds)
            let fm = FileManager.default
            let keys: [URLResourceKey] = [
                .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
                .fileSizeKey, .contentModificationDateKey, .volumeIdentifierKey,
            ]
            let rootVolumeID = try? root.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier

            // Shared counters for progress + caps. Single-threaded recursion in
            // this detached task, so plain vars are race-free.
            var scannedFiles = 0
            var scannedBytes: UInt64 = 0
            var nodeCount = 0
            var lastEmit = Date.distantPast

            func stop() -> Bool {
                Task.isCancelled || Date() > deadline || nodeCount > budget.maxTotalNodes
            }

            func emitProgress(force: Bool) {
                let now = Date()
                if force || now.timeIntervalSince(lastEmit) > 0.2 {
                    continuation.yield(.progress(scannedFiles: scannedFiles, scannedBytes: scannedBytes))
                    lastEmit = now
                }
            }

            func walk(_ dir: URL, depth: Int) -> (bytes: UInt64, files: Int, newest: Date, node: InventoryNode?) {
                if stop() { return (0, 0, .distantPast, nil) }

                var bytes: UInt64 = 0
                var files = 0
                var newest = Date.distantPast
                var retained: [InventoryNode] = []
                var foldedBytes: UInt64 = 0
                var foldedFiles = 0

                guard let contents = try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: keys, options: []
                ) else {
                    return (0, 0, .distantPast, nil)
                }

                for child in contents {
                    if stop() { break }
                    guard let values = try? child.resourceValues(forKeys: Set(keys)) else { continue }
                    if values.isSymbolicLink == true { continue }
                    // Don't cross into other volumes (network / external mounts).
                    if let rootVolumeID, let childVol = values.volumeIdentifier,
                       !childVol.isEqual(rootVolumeID) { continue }

                    if values.isDirectory == true {
                        let sub = walk(child, depth: depth + 1)
                        bytes &+= sub.bytes
                        files += sub.files
                        if sub.newest > newest { newest = sub.newest }
                        if let node = sub.node, depth < budget.maxDepth, node.totalBytes >= budget.minReportBytes {
                            retained.append(node)
                        } else {
                            foldedBytes &+= sub.bytes
                            foldedFiles += sub.files
                        }
                    } else {
                        let size = UInt64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                        bytes &+= size
                        files += 1
                        scannedFiles += 1
                        scannedBytes &+= size
                        if let modified = values.contentModificationDate, modified > newest {
                            newest = modified
                        }
                        emitProgress(force: false)
                    }
                }

                // Keep only the largest children; fold the rest.
                retained.sort { $0.totalBytes > $1.totalBytes }
                if retained.count > budget.maxChildrenPerNode {
                    for extra in retained[budget.maxChildrenPerNode...] {
                        foldedBytes &+= extra.totalBytes
                        foldedFiles += extra.fileCount
                    }
                    retained = Array(retained.prefix(budget.maxChildrenPerNode))
                }
                if foldedBytes >= budget.minReportBytes {
                    retained.append(InventoryNode(
                        url: dir.appendingPathComponent("(smaller items)", isDirectory: true),
                        totalBytes: foldedBytes, fileCount: foldedFiles,
                        modifiedAt: newest, isAggregate: true, topChildren: []
                    ))
                }

                nodeCount += 1
                let node = InventoryNode(url: dir, totalBytes: bytes, fileCount: files,
                                         modifiedAt: newest, isAggregate: false, topChildren: retained)
                return (bytes, files, newest, node)
            }

            let result = walk(root, depth: 0)
            emitProgress(force: true)
            continuation.yield(.finished(root: result.node))
            continuation.finish()
        }

        return stream
    }

    func cancel() { cancelLocked() }

    private func cancelLocked() {
        inFlight?.cancel()
        inFlight = nil
    }
}
