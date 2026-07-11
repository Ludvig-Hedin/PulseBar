import Foundation

/// Resolves the file inventory for one `StorageCategory`. Pure synchronous logic
/// so the call site can run it on whichever queue it wants. `ScanEngine` runs
/// each call inside a detached task with cancellation + deadline plumbed through.
///
/// Adapted from PureMac's `ScanEngine.scanCategory(_:)` (MIT). Kept in one file
/// so cross-category invariants (file cap, deadline, allowlist) are auditable
/// without jumping between files.
enum CategoryScanner {
    /// Retained as a shim for callers that scan a single category without a tier
    /// (e.g. the post-prune Docker rescan). The authoritative caps now live on
    /// `ScanBudget`.
    static var defaultDeadlineSeconds: TimeInterval { ScanBudget.default.perCategoryDeadlineSeconds }

    static func scan(category: StorageCategory,
                     budget: ScanBudget = .default,
                     deadline: Date,
                     cancellation: () -> Bool,
                     progress: ((UInt64, Int) -> Void)? = nil) -> CategoryResult {
        switch category {
        case .systemJunk, .userCache, .aiApps, .mailDownloads, .xcodeJunk:
            return scanStaticPaths(category: category,
                                   budget: budget,
                                   deadline: deadline,
                                   cancellation: cancellation,
                                   progress: progress)

        case .trash:
            return scanStaticPaths(category: .trash,
                                   budget: budget,
                                   deadline: deadline,
                                   cancellation: cancellation,
                                   progress: progress)

        case .largeFiles:
            return scanLargeFiles(budget: budget,
                                  deadline: deadline,
                                  cancellation: cancellation,
                                  progress: progress)

        case .brewCache:
            return scanBrewCache(budget: budget,
                                 deadline: deadline,
                                 cancellation: cancellation,
                                 progress: progress)

        case .nodeCache:
            return scanNodeCache(budget: budget,
                                 deadline: deadline,
                                 cancellation: cancellation,
                                 progress: progress)

        case .devArtifacts:
            return scanDevArtifacts(budget: budget,
                                    deadline: deadline,
                                    cancellation: cancellation,
                                    progress: progress)

        case .docker:
            return scanDocker()

        case .purgeableSpace:
            return scanPurgeable()

        case .smartScan:
            // SmartScan is orchestrated by ScanEngine — never called directly.
            return CategoryResult(category: .smartScan,
                                  items: [],
                                  totalSizeBytes: 0,
                                  scannedAt: .now,
                                  truncated: false,
                                  errors: [])
        }
    }

    // MARK: - Static path enumeration

    private static func scanStaticPaths(category: StorageCategory,
                                        budget: ScanBudget,
                                        deadline: Date,
                                        cancellation: () -> Bool,
                                        progress: ((UInt64, Int) -> Void)?) -> CategoryResult {
        var items: [CleanableItem] = []
        var total: UInt64 = 0
        var truncated = false
        var errors: [ScanError] = []

        let paths = Locations.staticPaths(for: category)
        for path in paths {
            if cancellation() {
                errors.append(ScanError(path: path.path, reason: .cancelled))
                break
            }
            let result = FileEnumerator.enumerate(
                root: path,
                category: category,
                maxFiles: budget.maxFilesPerCategory,
                deadline: deadline,
                cancellation: cancellation,
                progress: { running, count in
                    progress?(total &+ running, items.count + count)
                }
            )
            items.append(contentsOf: result.items)
            total &+= result.totalSizeBytes
            truncated = truncated || result.truncated
            errors.append(contentsOf: result.errors)
        }

        return CategoryResult(category: category,
                              items: items,
                              totalSizeBytes: total,
                              scannedAt: .now,
                              truncated: truncated,
                              errors: errors)
    }

    // MARK: - Large Files

    /// Walks a small set of high-yield roots looking for unusually large files.
    /// **Reveal-only in v1** — `StorageCategory.largeFiles.defaultDeletionMode`
    /// is unchanged from `.trash`, but the UI marks these items as non-cleanable
    /// to avoid foot-guns over user data the heuristics may misread.
    private static func scanLargeFiles(budget: ScanBudget,
                                       deadline: Date,
                                       cancellation: () -> Bool,
                                       progress: ((UInt64, Int) -> Void)?) -> CategoryResult {
        var items: [CleanableItem] = []
        var total: UInt64 = 0
        var truncated = false
        var errors: [ScanError] = []

        for root in Locations.staticPaths(for: .largeFiles) {
            if cancellation() { break }
            // Push the size filter into the enumerator so it doesn't burn the file cap
            // on small files in dense dev-tooling directories.
            let result = FileEnumerator.enumerate(
                root: root,
                category: .largeFiles,
                maxFiles: budget.largeFileMaxItems,
                minSizeBytes: budget.largeFileMinBytes,
                deadline: deadline,
                cancellation: cancellation,
                progress: nil
            )
            items.append(contentsOf: result.items)
            total &+= result.totalSizeBytes
            truncated = truncated || result.truncated
            errors.append(contentsOf: result.errors)

            if items.count >= budget.largeFileMaxItems {
                truncated = true
                break
            }
            progress?(total, items.count)
        }

        // Largest first so the top of the list is the most impactful.
        items.sort { $0.sizeBytes > $1.sizeBytes }
        if items.count > budget.largeFileMaxItems {
            items = Array(items.prefix(budget.largeFileMaxItems))
            truncated = true
        }

        return CategoryResult(category: .largeFiles,
                              items: items,
                              totalSizeBytes: total,
                              scannedAt: .now,
                              truncated: truncated,
                              errors: errors)
    }

    // MARK: - Brew

    private static func scanBrewCache(budget: ScanBudget,
                                      deadline: Date,
                                      cancellation: () -> Bool,
                                      progress: ((UInt64, Int) -> Void)?) -> CategoryResult {
        let candidates = Locations.cliCandidates(for: .brewCache)
        guard let brew = CommandRunner.resolveBinary(candidates) else {
            return emptyResult(.brewCache)
        }
        let output: CommandRunner.Output
        do {
            output = try CommandRunner.run(launchPath: brew, arguments: ["--cache"], timeout: 3)
        } catch {
            return emptyResult(.brewCache, errors: [ScanError(path: brew, reason: .ioError(String(describing: error)))])
        }
        guard output.exitCode == 0 else { return emptyResult(.brewCache) }
        let pathStr = output.trimmedStdout
        let url = URL(fileURLWithPath: pathStr, isDirectory: true)
        // Re-validate the CLI-resolved path before scanning.
        guard PathAllowlist.isScanAllowed(url) else { return emptyResult(.brewCache) }

        let result = FileEnumerator.enumerate(
            root: url,
            category: .brewCache,
            maxFiles: budget.maxFilesPerCategory,
            deadline: deadline,
            cancellation: cancellation,
            progress: progress
        )
        return CategoryResult(category: .brewCache,
                              items: result.items,
                              totalSizeBytes: result.totalSizeBytes,
                              scannedAt: .now,
                              truncated: result.truncated,
                              errors: result.errors)
    }

    // MARK: - Node / npm / yarn / pnpm

    private static func scanNodeCache(budget: ScanBudget,
                                      deadline: Date,
                                      cancellation: () -> Bool,
                                      progress: ((UInt64, Int) -> Void)?) -> CategoryResult {
        var items: [CleanableItem] = []
        var total: UInt64 = 0
        var errors: [ScanError] = []
        var truncated = false
        var scannedRoots = Set<String>()

        let tools: [(name: String, candidates: [String], args: [String])] = [
            ("npm", ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"], ["config", "get", "cache"]),
            ("yarn", ["/opt/homebrew/bin/yarn", "/usr/local/bin/yarn"], ["cache", "dir"]),
            ("pnpm", ["/opt/homebrew/bin/pnpm", "/usr/local/bin/pnpm"], ["store", "path"]),
        ]

        func appendScan(root: URL) {
            guard !cancellation() else { return }
            let url = root.resolvingSymlinksInPath().standardizedFileURL
            guard scannedRoots.insert(url.path).inserted else { return }
            guard PathAllowlist.isScanAllowed(url) else { return }

            let result = FileEnumerator.enumerate(
                root: url,
                category: .nodeCache,
                maxFiles: budget.maxFilesPerCategory,
                deadline: deadline,
                cancellation: cancellation,
                progress: { running, count in
                    progress?(total &+ running, items.count + count)
                }
            )
            items.append(contentsOf: result.items)
            total &+= result.totalSizeBytes
            truncated = truncated || result.truncated
            errors.append(contentsOf: result.errors)
        }

        for tool in tools {
            if cancellation() { break }
            guard let bin = CommandRunner.resolveBinary(tool.candidates) else { continue }
            guard let output = try? CommandRunner.run(launchPath: bin, arguments: tool.args, timeout: 3),
                  output.exitCode == 0 else { continue }
            appendScan(root: URL(fileURLWithPath: output.trimmedStdout, isDirectory: true))
        }

        for root in Locations.staticPaths(for: .nodeCache) {
            if cancellation() { break }
            appendScan(root: root)
        }

        return CategoryResult(category: .nodeCache,
                              items: items,
                              totalSizeBytes: total,
                              scannedAt: .now,
                              truncated: truncated,
                              errors: errors)
    }

    // MARK: - Developer artifacts

    /// Deep-Scan-only. Finds whole build/cache directories (`node_modules`,
    /// `target`, `.venv`, …) across the home folder via `ArtifactEnumerator`.
    private static func scanDevArtifacts(budget: ScanBudget,
                                         deadline: Date,
                                         cancellation: () -> Bool,
                                         progress: ((UInt64, Int) -> Void)?) -> CategoryResult {
        let result = ArtifactEnumerator.enumerate(
            roots: Locations.devArtifactRoots,
            budget: budget,
            deadline: deadline,
            cancellation: cancellation,
            progress: progress
        )
        return CategoryResult(category: .devArtifacts,
                              items: result.items,
                              totalSizeBytes: result.totalSizeBytes,
                              scannedAt: .now,
                              truncated: result.truncated,
                              errors: result.errors)
    }

    // MARK: - Docker

    /// Docker isn't enumerated as files; we surface reclaimable bytes from
    /// `docker system df`. Cleanup uses `docker system prune` rather than
    /// FileManager deletion.
    private static func scanDocker() -> CategoryResult {
        guard let report = DockerProbe.read() else {
            return emptyResult(.docker, errors: [
                ScanError(path: "docker", reason: .ioError("Docker CLI is unavailable or the daemon is not running"))
            ])
        }
        return CategoryResult(category: .docker,
                              items: [],
                              totalSizeBytes: report.reclaimableBytes,
                              scannedAt: .now,
                              truncated: false,
                              errors: [])
    }

    // MARK: - Purgeable

    /// Purgeable space is informational only — macOS reclaims it automatically.
    /// We surface the size so users understand why "Free" doesn't match expectations.
    private static func scanPurgeable() -> CategoryResult {
        let probe = PurgeableSpaceProbe()
        let usage = probe.read()
        let bytes = usage?.purgeableBytes ?? 0
        return CategoryResult(category: .purgeableSpace,
                              items: [],
                              totalSizeBytes: bytes,
                              scannedAt: .now,
                              truncated: false,
                              errors: [])
    }

    // MARK: - Helpers

    private static func emptyResult(_ category: StorageCategory, errors: [ScanError] = []) -> CategoryResult {
        CategoryResult(category: category,
                       items: [],
                       totalSizeBytes: 0,
                       scannedAt: .now,
                       truncated: false,
                       errors: errors)
    }
}
