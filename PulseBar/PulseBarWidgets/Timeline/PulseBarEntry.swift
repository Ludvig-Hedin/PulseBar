import WidgetKit

struct PulseBarEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    /// True once the snapshot is old enough that the widget should show its
    /// dimmed/"Open PulseBar" state rather than trusting the numbers. Threshold
    /// is slightly past `WidgetBridgeService`'s 5-minute heartbeat so a live app
    /// never flickers stale between reloads.
    var isStale: Bool {
        guard let snapshot else { return true }
        return date.timeIntervalSince(snapshot.generatedAt) > 6 * 60
    }
}
