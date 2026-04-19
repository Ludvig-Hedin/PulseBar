import Foundation

/// Tabs available in the main dashboard sidebar and navigation.
/// NOTE: This file is what the Xcode project currently references.
/// Feel free to rename the file to `DashboardTab.swift` in Xcode (right-click → Rename)
/// and delete the placeholder `DashboardTab.swift` sitting next to it.
public enum DashboardTab: String, CaseIterable, Hashable, Identifiable {
    case overview
    case processes
    case devServers
    case alerts
    case settings

    public var id: Self { self }

    /// Human-readable title for the tab.
    public var title: String {
        switch self {
        case .overview: return "Overview"
        case .processes: return "Processes"
        case .devServers: return "Dev Servers"
        case .alerts: return "Alerts"
        case .settings: return "Settings"
        }
    }

    /// SF Symbol for this tab in the sidebar.
    public var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .processes: return "list.bullet.rectangle"
        case .devServers: return "server.rack"
        case .alerts: return "bell"
        case .settings: return "gearshape"
        }
    }
}
