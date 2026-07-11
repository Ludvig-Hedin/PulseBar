import Foundation

/// Resolves (and lazily creates) PulseBar's Application Support directory.
///
/// The app is not sandboxed, so this is the real
/// `~/Library/Application Support/PulseBar/` — a natural home for data too large
/// for UserDefaults (e.g. per-scan history files).
enum ApplicationSupport {
    /// Returns `~/Library/Application Support/PulseBar/<subpath>`, creating every
    /// intermediate directory. Returns nil only if creation fails.
    static func directory(subpath: String = "") -> URL? {
        let base = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PulseBar", isDirectory: true)
        let dir = subpath.isEmpty ? base : base.appendingPathComponent(subpath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }
}
