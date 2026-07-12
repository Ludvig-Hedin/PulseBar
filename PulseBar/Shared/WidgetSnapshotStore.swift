import Foundation

/// Reads/writes `WidgetSnapshot` to the shared App Group container. Deliberately
/// `Foundation`-only (no `WidgetKit` import) so it compiles into both the main
/// app and the sandboxed widget extension without pulling in WidgetKit on the
/// app side just for storage.
enum WidgetSnapshotStore {
    static let appGroupID = "group.com.ludvighedin.PulseBar"
    private static let key = "widget.snapshot.v1"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    /// Returns `nil` if nothing has been written yet, or if the stored payload
    /// no longer matches `WidgetSnapshot`'s shape (e.g. after a schema change) —
    /// callers should treat `nil` as "no data yet", not as an error.
    static func read() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
