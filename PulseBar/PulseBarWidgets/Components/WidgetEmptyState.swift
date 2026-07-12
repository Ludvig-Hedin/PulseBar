import SwiftUI

/// Overlay shown when a widget has no snapshot yet, or the snapshot is stale
/// (PulseBar hasn't refreshed in a while — most likely the app isn't running).
struct WidgetEmptyState: View {
    var body: some View {
        Label("Open PulseBar", systemImage: "arrow.up.forward.app")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Dims widget content to signal "last known values, not live" without
/// hiding them outright.
struct StaleDimmer: ViewModifier {
    let isStale: Bool
    func body(content: Content) -> some View {
        content.opacity(isStale ? 0.45 : 1)
    }
}

extension View {
    func staleDimmed(_ isStale: Bool) -> some View {
        modifier(StaleDimmer(isStale: isStale))
    }
}
