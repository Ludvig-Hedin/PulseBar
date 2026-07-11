import Foundation

/// Tabs available in the main dashboard sidebar and navigation.
public enum DashboardTab: String, CaseIterable, Hashable, Identifiable {
    case overview
    case processes
    case devServers
    case alerts
    case storage
    case storageHistory
    case settings

    public var id: Self { self }

    /// Human-readable title for the tab.
    public var title: String {
        switch self {
        case .overview: return "Overview"
        case .processes: return "Processes"
        case .devServers: return "Dev Servers"
        case .alerts: return "Alerts"
        case .storage: return "Storage"
        case .storageHistory: return "History & Trends"
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
        case .storage: return "internaldrive.fill"
        case .storageHistory: return "chart.xyaxis.line"
        case .settings: return "gearshape"
        }
    }

    /// Sidebar grouping. Drives the Section header in `MainDashboardView`.
    public var group: DashboardTabGroup {
        switch self {
        case .overview, .processes, .devServers, .alerts: return .performance
        case .storage, .storageHistory: return .storage
        case .settings: return .performance
        }
    }
}

/// Visual group used to bucket tabs in the sidebar.
public enum DashboardTabGroup: String, CaseIterable, Hashable {
    case performance
    case storage

    public var title: String {
        switch self {
        case .performance: return "Performance"
        case .storage: return "Storage"
        }
    }
}
