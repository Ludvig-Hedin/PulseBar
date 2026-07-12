import WidgetKit

/// Shared across all six widget kinds — they all read the same `WidgetSnapshot`,
/// only the rendered view differs. Fixed content only (no `AppIntents`/user
/// configuration in v1).
struct PulseBarTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseBarEntry {
        PulseBarEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseBarEntry) -> Void) {
        let snapshot = context.isPreview ? .placeholder : WidgetSnapshotStore.read()
        completion(PulseBarEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseBarEntry>) -> Void) {
        let entry = PulseBarEntry(date: .now, snapshot: WidgetSnapshotStore.read())
        // WidgetBridgeService calls reloadAllTimelines() on meaningful change, so this
        // is a fallback poll only — keeps the widget from going silent forever if a
        // reload notification is ever missed.
        let nextPoll = Date().addingTimeInterval(10 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextPoll)))
    }
}
