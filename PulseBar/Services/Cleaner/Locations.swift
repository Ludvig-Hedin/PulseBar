import Foundation

/// Hardcoded directory database for the cleaner subsystem.
///
/// Inspired by PureMac's `Locations.swift` (MIT-licensed). Trimmed and re-grouped
/// to match PulseBar's category set. Keeping this in one file makes the surface
/// auditable.
enum Locations {
    /// User's home directory.
    static let home: URL = FileManager.default.homeDirectoryForCurrentUser
    /// `~/Library`.
    static var userLibrary: URL { home.appendingPathComponent("Library", isDirectory: true) }

    /// Static path entries per category. Some categories (Brew, Node, Docker) resolve
    /// their paths dynamically via CLI in `CategoryScanner`.
    static func staticPaths(for category: StorageCategory) -> [URL] {
        switch category {
        case .systemJunk:
            return [
                URL(fileURLWithPath: "/Library/Caches", isDirectory: true),
                URL(fileURLWithPath: "/Library/Logs", isDirectory: true),
                URL(fileURLWithPath: "/private/var/log", isDirectory: true),
                URL(fileURLWithPath: "/private/tmp", isDirectory: true),
                URL(fileURLWithPath: "/private/var/tmp", isDirectory: true),
            ]

        case .userCache:
            return [
                userLibrary.appendingPathComponent("Caches", isDirectory: true),
                userLibrary.appendingPathComponent("Logs", isDirectory: true),
                // XDG-style cache used by many dev tools (pip, poetry, pre-commit, etc.)
                home.appendingPathComponent(".cache", isDirectory: true),
                // VSCode / Cursor transpile & extension caches
                userLibrary.appendingPathComponent("Application Support/Code/CachedData", isDirectory: true),
                userLibrary.appendingPathComponent("Application Support/Code/CachedExtensions", isDirectory: true),
                userLibrary.appendingPathComponent("Application Support/Cursor/CachedData", isDirectory: true),
                userLibrary.appendingPathComponent("Application Support/Cursor/CachedExtensions", isDirectory: true),
            ]

        case .aiApps:
            return [
                home.appendingPathComponent(".ollama/logs", isDirectory: true),
                home.appendingPathComponent(".ollama/history", isDirectory: false),
                userLibrary.appendingPathComponent("Application Support/LM Studio/Cache", isDirectory: true),
                userLibrary.appendingPathComponent("Caches/com.anthropic.claudefordesktop", isDirectory: true),
                userLibrary.appendingPathComponent("Caches/com.openai.chat", isDirectory: true),
                // Claude Code agent-server resources cache
                userLibrary.appendingPathComponent("Caches/com.anthropic.claude", isDirectory: true),
                // Perplexity, Copilot, and other AI app caches
                userLibrary.appendingPathComponent("Caches/com.perplexity.mac", isDirectory: true),
                userLibrary.appendingPathComponent("Caches/com.github.GitHubCopilot", isDirectory: true),
            ]

        case .mailDownloads:
            // Modern macOS (Sierra+) only writes to the sandboxed Containers path.
            // The legacy `~/Library/Mail Downloads` path no longer exists; keep one entry.
            return [
                userLibrary.appendingPathComponent("Containers/com.apple.mail/Data/Library/Mail Downloads", isDirectory: true),
            ]

        case .trash:
            return [
                home.appendingPathComponent(".Trash", isDirectory: true),
            ]

        case .largeFiles:
            // Walked separately — see `CategoryScanner.scanLargeFiles`. Anchors here are roots
            // explicitly allowed for the recursive walk.
            return [
                home.appendingPathComponent("Library/Developer", isDirectory: true),
                home.appendingPathComponent("Library/Containers", isDirectory: true),
            ]

        case .xcodeJunk:
            let dev = home.appendingPathComponent("Library/Developer/Xcode", isDirectory: true)
            let coreSim = home.appendingPathComponent("Library/Developer/CoreSimulator", isDirectory: true)
            return [
                dev.appendingPathComponent("DerivedData", isDirectory: true),
                dev.appendingPathComponent("Archives", isDirectory: true),
                dev.appendingPathComponent("iOS DeviceSupport", isDirectory: true),
                dev.appendingPathComponent("watchOS DeviceSupport", isDirectory: true),
                dev.appendingPathComponent("tvOS DeviceSupport", isDirectory: true),
                dev.appendingPathComponent("visionOS DeviceSupport", isDirectory: true),
                coreSim.appendingPathComponent("Caches", isDirectory: true),
                // Xcode's own download/build cache (often 1-4 GB)
                userLibrary.appendingPathComponent("Caches/com.apple.dt.Xcode", isDirectory: true),
                // Swift Package Manager resolved build products
                home.appendingPathComponent("Library/org.swift.swiftpm/cache", isDirectory: true),
                // CocoaPods download cache
                home.appendingPathComponent(".cocoapods/repos", isDirectory: true),
            ]

        case .nodeCache:
            // npm/yarn/pnpm are resolved dynamically; add static extras.
            return [
                // Rust/Cargo download cache — safe to wipe; cargo re-fetches on next build
                home.appendingPathComponent(".cargo/registry/cache", isDirectory: true),
                home.appendingPathComponent(".cargo/registry/src", isDirectory: true),
                // Gradle download cache
                home.appendingPathComponent(".gradle/caches", isDirectory: true),
                // Maven local repo
                home.appendingPathComponent(".m2/repository", isDirectory: true),
            ]

        case .devArtifacts:
            return devArtifactRoots

        case .brewCache, .docker, .purgeableSpace, .smartScan:
            // Dynamic — scanner resolves via CommandRunner / system APIs.
            return []
        }
    }

    // MARK: - Developer artifacts (Deep Scan)

    /// Roots walked by the developer-artifact finder. The whole home folder —
    /// the walker prunes protected + noisy subtrees for speed, and
    /// `PathAllowlist` is the authority on what may actually be deleted.
    static var devArtifactRoots: [URL] { [home] }

    /// Unambiguous build/cache directory names, reported wherever they appear.
    static let unconditionalArtifactMarkers: Set<String> = [
        "node_modules", ".next", ".nuxt", "Pods", "DerivedData",
        ".venv", "__pycache__", ".pytest_cache", ".mypy_cache",
        ".turbo", ".parcel-cache",
    ]

    /// Common words that are only treated as artifacts when a sibling project
    /// manifest proves the parent directory is a real project (avoids nuking a
    /// user folder literally named "build" or "target").
    static let projectScopedArtifactMarkers: Set<String> = [
        "dist", "build", "target", "venv", ".gradle",
    ]

    /// Files whose presence marks a directory as a genuine project root.
    static let projectManifests: Set<String> = [
        "package.json", "Cargo.toml", "go.mod", "pom.xml",
        "build.gradle", "build.gradle.kts", "Podfile", "pyproject.toml",
        "requirements.txt", "setup.py", "Gemfile", "composer.json",
        "pubspec.yaml", "tsconfig.json",
    ]

    /// Directory names the artifact walk never descends into. Performance only —
    /// the safety boundary is `PathAllowlist`.
    static let artifactTraversalSkips: Set<String> = [
        "Library", "Applications", ".Trash", ".git", ".svn", ".hg",
    ]

    /// Candidate launch paths for the binary backing a category.
    static func cliCandidates(for category: StorageCategory) -> [String] {
        switch category {
        case .brewCache:
            return ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        case .nodeCache:
            // npm/yarn/pnpm: any present binaries are used. Caller iterates.
            return ["/opt/homebrew/bin/npm", "/usr/local/bin/npm",
                    "/opt/homebrew/bin/yarn", "/usr/local/bin/yarn",
                    "/opt/homebrew/bin/pnpm", "/usr/local/bin/pnpm"]
        case .docker:
            return ["/opt/homebrew/bin/docker", "/usr/local/bin/docker"]
        default:
            return []
        }
    }
}
