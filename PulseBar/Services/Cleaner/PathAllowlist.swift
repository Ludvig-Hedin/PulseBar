import Foundation

/// Gatekeeper for both scans and admin-escalated deletions.
///
/// The cleaner subsystem refuses to look at or touch any path that fails
/// `isScanAllowed`. The admin-escalation path additionally requires
/// `isAdminEscalationAllowed`, which is intentionally narrower.
///
/// Both predicates resolve symlinks before checking, so a symlink under
/// `~/Library/Caches` that points to `~/Documents` is treated as `~/Documents`
/// and rejected.
enum PathAllowlist {
    /// User-facing directories the cleaner must never touch, even if a symlink
    /// or CLI-resolved path points here.
    private static var protectedDirectories: [URL] {
        let home = Locations.home
        return [
            home.appendingPathComponent("Documents", isDirectory: true),
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true),
            home.appendingPathComponent("Movies", isDirectory: true),
            home.appendingPathComponent("Music", isDirectory: true),
            home.appendingPathComponent("Pictures", isDirectory: true),
            home.appendingPathComponent("Public", isDirectory: true),
            home.appendingPathComponent(".ssh", isDirectory: true),
            home.appendingPathComponent(".gnupg", isDirectory: true),
            home.appendingPathComponent(".aws", isDirectory: true),
            home.appendingPathComponent(".kube", isDirectory: true),
            home.appendingPathComponent(".config", isDirectory: true),
        ]
    }

    /// Directory prefixes the cleaner is allowed to enumerate.
    private static var scanRoots: [URL] {
        let home = Locations.home
        return [
            // System
            URL(fileURLWithPath: "/Library/Caches", isDirectory: true),
            URL(fileURLWithPath: "/Library/Logs", isDirectory: true),
            URL(fileURLWithPath: "/private/var/log", isDirectory: true),
            URL(fileURLWithPath: "/private/tmp", isDirectory: true),
            URL(fileURLWithPath: "/private/var/tmp", isDirectory: true),
            URL(fileURLWithPath: "/private/var/folders", isDirectory: true),
            // User Library — explicitly named subtrees only
            home.appendingPathComponent("Library/Caches", isDirectory: true),
            home.appendingPathComponent("Library/Logs", isDirectory: true),
            home.appendingPathComponent("Library/Developer", isDirectory: true),
            home.appendingPathComponent("Library/Mail Downloads", isDirectory: true),
            home.appendingPathComponent("Library/Containers", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/LM Studio/Cache", isDirectory: true),
            // Other
            home.appendingPathComponent(".Trash", isDirectory: true),
            home.appendingPathComponent(".npm", isDirectory: true),
            home.appendingPathComponent(".cache", isDirectory: true),
            home.appendingPathComponent(".yarn/cache", isDirectory: true),
            home.appendingPathComponent("Library/pnpm", isDirectory: true),
            home.appendingPathComponent(".ollama/logs", isDirectory: true),
            // Rust/Cargo — download cache only (not ~/.cargo/bin)
            home.appendingPathComponent(".cargo/registry", isDirectory: true),
            // Build tool caches
            home.appendingPathComponent(".gradle/caches", isDirectory: true),
            home.appendingPathComponent(".m2/repository", isDirectory: true),
            home.appendingPathComponent(".cocoapods/repos", isDirectory: true),
            home.appendingPathComponent("Library/org.swift.swiftpm/cache", isDirectory: true),
            // VSCode / Cursor transpile caches
            home.appendingPathComponent("Library/Application Support/Code/CachedData", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Code/CachedExtensions", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Cursor/CachedData", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Cursor/CachedExtensions", isDirectory: true),
        ]
    }

    /// Narrow allowlist for paths that may be deleted via `do shell script ... with administrator privileges`.
    private static var adminEscalationRoots: [URL] {
        [
            URL(fileURLWithPath: "/Library/Caches", isDirectory: true),
            URL(fileURLWithPath: "/Library/Logs", isDirectory: true),
            URL(fileURLWithPath: "/private/var/log", isDirectory: true),
            URL(fileURLWithPath: "/private/tmp", isDirectory: true),
            URL(fileURLWithPath: "/private/var/folders", isDirectory: true),
            Locations.home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true),
        ]
    }

    /// Returns true if `url` is somewhere the cleaner may read or schedule for delete.
    static func isScanAllowed(_ url: URL) -> Bool {
        guard let resolved = resolvedPath(url) else { return false }
        if containsPathSeparatorEscape(resolved) { return false }
        if isProtected(resolved) { return false }
        if isPulseBarOwned(resolved) { return false }
        return scanRoots.contains(where: { isUnder(resolved, root: normalize($0)) })
    }

    /// Returns true if `url` is on the (narrower) admin-escalation allowlist.
    static func isAdminEscalationAllowed(_ url: URL) -> Bool {
        guard isScanAllowed(url), let resolved = resolvedPath(url) else { return false }
        return adminEscalationRoots.contains(where: { isUnder(resolved, root: normalize($0)) })
    }

    // MARK: - Developer artifacts (Deep Scan)

    /// Recognised artifact directory names. The delete gate requires the leaf
    /// name to be one of these, so only whole `node_modules`/`build`/… folders
    /// can be removed — never an arbitrary file the walk happened to surface.
    static var artifactMarkers: Set<String> {
        Locations.unconditionalArtifactMarkers.union(Locations.projectScopedArtifactMarkers)
    }

    /// READ gate for the developer-artifact finder. Broader than `isScanAllowed`
    /// (spans the whole home folder) but still rejects protected user
    /// directories, symlink escapes, and PulseBar-owned paths. Read-only — it
    /// does NOT authorise deletion.
    static func isArtifactScanAllowed(_ url: URL) -> Bool {
        guard let resolved = resolvedPath(url) else { return false }
        if containsPathSeparatorEscape(resolved) { return false }
        if isProtected(resolved) { return false }
        if isPulseBarOwned(resolved) { return false }
        return Locations.devArtifactRoots.contains(where: { isUnder(resolved, root: normalize($0)) })
    }

    /// DELETE gate for developer artifacts. True only when the path is inside a
    /// dev root (and not protected) AND its own leaf name is a recognised
    /// artifact marker. Unconditional markers (`node_modules`, `Pods`, …) pass
    /// directly; project-scoped markers (`build`, `dist`, `target`, `venv`,
    /// `.gradle`) additionally require a sibling project manifest — so this last
    /// line of defense is exactly as strict as the discovery walk, and a user
    /// folder merely named `build` can never be trashed.
    static func isArtifactDeleteAllowed(_ url: URL) -> Bool {
        guard isArtifactScanAllowed(url), let resolved = resolvedPath(url) else { return false }
        let name = (resolved as NSString).lastPathComponent
        if Locations.unconditionalArtifactMarkers.contains(name) { return true }
        if Locations.projectScopedArtifactMarkers.contains(name) {
            return parentHasProjectManifest(URL(fileURLWithPath: resolved))
        }
        return false
    }

    /// True if the directory's parent contains a project manifest (package.json,
    /// Cargo.toml, …), i.e. it's a real project — not a coincidentally-named dir.
    private static func parentHasProjectManifest(_ dir: URL) -> Bool {
        let parent = dir.deletingLastPathComponent()
        for manifest in Locations.projectManifests {
            if FileManager.default.fileExists(atPath: parent.appendingPathComponent(manifest).path) {
                return true
            }
        }
        return false
    }

    /// Directory-boundary-aware prefix check. Prevents `~/.cargo/registry-backup`
    /// from matching the `~/.cargo/registry` allowlist entry.
    private static func isUnder(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    /// Filename-level safety check used by the AppleScript escalation path.
    ///
    /// The escalation builds: `osascript -e 'do shell script "<cmd>" with administrator privileges'`
    /// where `<cmd>` is `/bin/rm -rf -- '<path1>' '<path2>' …`. Two parsers see the string:
    /// AppleScript (double-quoted) and `/bin/sh` (single-quoted within the AppleScript string).
    /// We refuse any path containing characters either parser treats specially, even though
    /// our quoting strategy *should* neutralise most of them. Belt-and-suspenders.
    static func isSafeForShellEscalation(_ url: URL) -> Bool {
        let path = url.path
        // Anything a shell or AppleScript double-quoted string treats specially.
        // Whitespace is allowed (paths legitimately contain spaces) because single-quote
        // wrapping handles it, but tabs/newlines remain banned.
        let bannedCharacters: Set<Character> = [
            "'", "\"", "`", "\\",
            "$", ";", "|", "&", "<", ">", "(", ")",
            "*", "?", "[", "]", "{", "}",
            "!", "#", "~",
            "\n", "\r", "\t",
        ]
        if path.contains(where: { bannedCharacters.contains($0) }) { return false }
        if path.contains("..") { return false }
        if path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) { return false }
        return true
    }

    // MARK: - Helpers

    private static func resolvedPath(_ url: URL) -> String? {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        return resolved.path
    }

    private static func normalize(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func isProtected(_ path: String) -> Bool {
        for protected in protectedDirectories {
            let prefix = normalize(protected)
            if path == prefix || path.hasPrefix(prefix + "/") { return true }
        }
        return false
    }

    private static func isPulseBarOwned(_ path: String) -> Bool {
        let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        if path.hasPrefix(bundlePath) { return true }
        // Refuse to wipe our own caches.
        if let bundleID = Bundle.main.bundleIdentifier {
            let ownCache = Locations.userLibrary
                .appendingPathComponent("Caches", isDirectory: true)
                .appendingPathComponent(bundleID, isDirectory: true)
                .path
            if path.hasPrefix(ownCache) { return true }
        }
        // Apple icon-services cache — corruption landmine.
        let iconServices = Locations.userLibrary
            .appendingPathComponent("Caches/com.apple.iconservices", isDirectory: true)
            .path
        if path.hasPrefix(iconServices) { return true }
        return false
    }

    private static func containsPathSeparatorEscape(_ path: String) -> Bool {
        // `..` already collapsed by `standardizedFileURL`; this is a belt-and-suspenders
        // check in case standardisation ever changes.
        path.contains("/../") || path.hasSuffix("/..")
    }
}
