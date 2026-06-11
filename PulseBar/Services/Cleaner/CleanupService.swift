import Foundation

/// Deletion engine for the cleaner subsystem.
///
/// Three deletion modes:
/// - `.trash`: move to `~/.Trash` via `FileManager.trashItem`. Reversible.
/// - `.permanent`: `FileManager.removeItem`. Not reversible.
/// - `.adminPermanent`: try `.permanent`; on EACCES/EPERM, fall back to AppleScript
///   admin escalation. Only allowed for paths on `PathAllowlist.isAdminEscalationAllowed`.
///
/// Every deletion runs through:
/// 1. Symlink resolution.
/// 2. `PathAllowlist.isScanAllowed` (and `isAdminEscalationAllowed` when applicable).
/// 3. Re-stat (TOCTOU mitigation).
/// 4. Size sanity check (refuses if the file grew >10x since scan).
/// 5. Execution.
actor CleanupService {
    /// Max paths per AppleScript escalation batch. Bounds the command line length.
    private static let escalationBatchSize = 50

    /// Fixed reason string shown to the user in the macOS admin prompt.
    private static let escalationReason = "PulseBar needs administrator access to remove protected system caches you just confirmed."

    struct EscalationError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    func delete(items: [CleanableItem], mode: DeletionMode) async -> [DeletionRecord] {
        var records: [DeletionRecord] = []
        var escalationCandidates: [(item: CleanableItem, resolved: URL)] = []

        for item in items {
            let resolved = item.url.resolvingSymlinksInPath().standardizedFileURL

            guard PathAllowlist.isScanAllowed(resolved) else {
                records.append(makeRecord(item: item, mode: mode, result: .refused("Path not on allowlist")))
                continue
            }

            if mode == .adminPermanent && !PathAllowlist.isAdminEscalationAllowed(resolved) {
                records.append(makeRecord(item: item, mode: mode, result: .refused("Admin escalation not allowed for this path")))
                continue
            }

            guard let attrs = try? FileManager.default.attributesOfItem(atPath: resolved.path) else {
                records.append(makeRecord(item: item, mode: mode, result: .failed("File no longer exists")))
                continue
            }

            let currentSize = (attrs[.size] as? UInt64) ?? 0
            // Defence against "user just dropped a 50GB file at this path between scan and clean".
            // Only applies if we had a non-trivial original size to compare against.
            if item.sizeBytes > 1_024 && currentSize > item.sizeBytes * 10 {
                records.append(makeRecord(item: item, mode: mode, result: .refused("File grew unexpectedly since scan")))
                continue
            }

            switch mode {
            case .trash:
                records.append(performTrash(item: item, resolved: resolved))
            case .permanent:
                records.append(performPermanent(item: item, resolved: resolved))
            case .adminPermanent:
                // Try permanent first; queue for escalation only on permission failure.
                let attempt = performPermanent(item: item, resolved: resolved)
                if case .succeeded = attempt.result {
                    records.append(attempt)
                } else if let msg = attempt.result.failureMessage,
                          msg.contains("permission") || msg.contains("EACCES") || msg.contains("EPERM") {
                    escalationCandidates.append((item, resolved))
                } else {
                    records.append(attempt)
                }
            }
        }

        if !escalationCandidates.isEmpty {
            let batches = stride(from: 0, to: escalationCandidates.count, by: Self.escalationBatchSize).map {
                Array(escalationCandidates[$0..<min($0 + Self.escalationBatchSize, escalationCandidates.count)])
            }
            for batch in batches {
                let safe = batch.filter { PathAllowlist.isSafeForShellEscalation($0.resolved) }
                let unsafe = batch.filter { !PathAllowlist.isSafeForShellEscalation($0.resolved) }
                for skipped in unsafe {
                    records.append(makeRecord(item: skipped.item, mode: .adminPermanent,
                                              result: .refused("Path contains unsafe characters for shell escalation")))
                }
                if !safe.isEmpty {
                    let escalationURLs: [URL] = safe.map { $0.resolved }
                    let result = escalateAndDelete(escalationURLs)
                    switch result {
                    case .success(let deletedURLs):
                        let deletedSet: Set<String> = Set(deletedURLs.map { $0.path })
                        for entry in safe {
                            let succeeded = deletedSet.contains(entry.resolved.path)
                            records.append(makeRecord(
                                item: entry.item,
                                mode: .adminPermanent,
                                result: succeeded ? .succeeded : .failed("Admin escalation reported failure")
                            ))
                        }
                    case .failure(let error):
                        for entry in safe {
                            records.append(makeRecord(item: entry.item, mode: .adminPermanent,
                                                      result: .failed("Admin escalation: \(error)")))
                        }
                    }
                }
            }
        }

        return records
    }

    /// Empties `~/.Trash`. Distinct flow from `.trash` deletion: this is the
    /// "Empty Trash" action invoked from the Trash category.
    func emptyTrash() -> [DeletionRecord] {
        let trash = Locations.home.appendingPathComponent(".Trash", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: trash,
                                                                          includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else {
            return []
        }
        var records: [DeletionRecord] = []
        for url in contents {
            let size = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0
            do {
                try FileManager.default.removeItem(at: url)
                records.append(DeletionRecord(url: url, sizeBytes: UInt64(size),
                                              category: .trash, mode: .permanent,
                                              result: .succeeded))
            } catch {
                records.append(DeletionRecord(url: url, sizeBytes: UInt64(size),
                                              category: .trash, mode: .permanent,
                                              result: .failed(error.localizedDescription)))
            }
        }
        return records
    }

    // MARK: - Per-mode primitives

    private func performTrash(item: CleanableItem, resolved: URL) -> DeletionRecord {
        do {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: resolved, resultingItemURL: &resultingURL)
            return makeRecord(item: item, mode: .trash, result: .succeeded)
        } catch {
            return makeRecord(item: item, mode: .trash, result: .failed(error.localizedDescription))
        }
    }

    private func performPermanent(item: CleanableItem, resolved: URL) -> DeletionRecord {
        do {
            try FileManager.default.removeItem(at: resolved)
            return makeRecord(item: item, mode: .permanent, result: .succeeded)
        } catch {
            return makeRecord(item: item, mode: .permanent, result: .failed(error.localizedDescription))
        }
    }

    /// Runs `osascript -e 'do shell script "/bin/rm -rf -- <quoted paths>" with administrator privileges'`.
    /// Caller must have already passed every URL through `PathAllowlist.isAdminEscalationAllowed`
    /// and `PathAllowlist.isSafeForShellEscalation`.
    private func escalateAndDelete(_ urls: [URL]) -> Result<[URL], EscalationError> {
        // Single-quote-only quoting: each path becomes 'absolute/path'.
        // Safety pre-condition: PathAllowlist already rejected any path containing a single quote.
        let quoted = urls.map { "'\($0.path)'" }.joined(separator: " ")
        let shellCommand = "/bin/rm -rf -- \(quoted)"
        // AppleScript with administrator privileges. The reason string is fixed.
        let safeAppleScriptCommand = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = """
        do shell script "\(safeAppleScriptCommand)" with administrator privileges with prompt "\(Self.escalationReason)"
        """

        do {
            let output = try CommandRunner.run(
                launchPath: "/usr/bin/osascript",
                arguments: ["-e", appleScript],
                timeout: 60 // user-interactive prompt may delay completion
            )
            if output.exitCode == 0 {
                // We can't verify per-file success from osascript output alone;
                // re-stat each path and treat absent files as deleted.
                let deleted = urls.filter { !FileManager.default.fileExists(atPath: $0.path) }
                return .success(deleted)
            } else {
                let msg = output.stderr.isEmpty ? "exit \(output.exitCode)" : output.stderr
                return .failure(EscalationError(message: msg))
            }
        } catch {
            return .failure(EscalationError(message: String(describing: error)))
        }
    }

    private func makeRecord(item: CleanableItem,
                            mode: DeletionMode,
                            result: DeletionRecord.DeletionResult) -> DeletionRecord {
        DeletionRecord(url: item.url,
                       sizeBytes: item.sizeBytes,
                       category: item.category,
                       mode: mode,
                       result: result)
    }
}
