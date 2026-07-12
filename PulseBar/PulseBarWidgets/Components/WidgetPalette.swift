import SwiftUI

/// Mirrors `OverviewSection`'s fixed warn/critical bands so widget colors read
/// the same as the dashboard's `MetricCard`s. Deliberately not wired to
/// `AlertsService`'s user-configurable thresholds — those drive the in-app
/// alert list, a different job, and pulling `PreferencesService` into the
/// widget's refresh path would add complexity with no asked-for benefit.
enum WidgetPalette {
    static func tint(_ value: Double, warn: Double, critical: Double) -> Color {
        if value >= critical { return .red }
        if value >= warn { return .orange }
        return .green
    }

    static func battery(_ percent: Double) -> Color {
        percent < 20 ? .red : .green
    }
}
