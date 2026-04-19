import Foundation
import AppKit

/// Cached lookup for macOS app icons. Avoids hammering NSWorkspace on every redraw.
/// Keyed by bundle identifier first, then falls back to PID → executable path.
@MainActor
final class AppIconService {
    static let shared = AppIconService()

    private var byBundleID: [String: NSImage] = [:]
    private var byPID: [Int32: NSImage] = [:]

    private init() {}

    func icon(for row: ProcessRow) -> NSImage? {
        if let bid = row.bundleIdentifier, let cached = byBundleID[bid] {
            return cached
        }
        if let cached = byPID[row.pid] {
            return cached
        }

        // Try NSRunningApplication first (cheap, already has a cached icon).
        if let running = NSRunningApplication(processIdentifier: row.pid), let icon = running.icon {
            byPID[row.pid] = icon
            if let bid = row.bundleIdentifier { byBundleID[bid] = icon }
            return icon
        }

        // Fallback: use the executable's icon (CLI/background processes).
        if let path = row.executablePath {
            let icon = NSWorkspace.shared.icon(forFile: path)
            byPID[row.pid] = icon
            if let bid = row.bundleIdentifier { byBundleID[bid] = icon }
            return icon
        }

        return nil
    }

    /// Drop entries for PIDs that are no longer running. Call occasionally to bound memory.
    func prune(activePIDs: Set<Int32>) {
        byPID = byPID.filter { activePIDs.contains($0.key) }
    }
}
