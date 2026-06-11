import Foundation
import AppKit

/// Probes a small set of TCC-protected paths to infer whether the app has
/// Full Disk Access. Result is memoised for 30 seconds because the user can
/// grant FDA mid-session and we want to notice without spamming reads.
actor FullDiskAccessDetector {
    private var cached: (granted: Bool, at: Date)?
    private static let cacheTTL: TimeInterval = 30

    /// Returns the latest FDA status, recomputing if the cache has expired.
    func hasFullDiskAccess() -> Bool {
        if let cached, Date().timeIntervalSince(cached.at) < Self.cacheTTL {
            return cached.granted
        }
        let granted = Self.probe()
        cached = (granted, .now)
        return granted
    }

    /// Forces a fresh probe (used by "I've granted access" button).
    func recheck() -> Bool {
        cached = nil
        return hasFullDiskAccess()
    }

    /// Opens the macOS Privacy & Security → Full Disk Access pane in System Settings.
    nonisolated static func openSystemSettings() {
        // `x-apple.systempreferences:` URL handler — works on macOS 13+.
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    /// Walks three FDA-gated probe targets. If at least one returns data, FDA is on.
    /// If all three fail with permission errors (or don't exist), FDA is off.
    private static func probe() -> Bool {
        let candidates: [URL] = [
            URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db"),
            Locations.home.appendingPathComponent("Library/Safari/CloudTabs.db"),
            Locations.home.appendingPathComponent("Library/Mail"),
        ]
        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            // Close the descriptor deterministically — `FileHandle` deinit closes
            // eventually, but probe runs every 30 s and we don't want to rely on
            // autorelease pool timing for file descriptors.
            try? handle.close()
            return true
        }
        return false
    }
}
