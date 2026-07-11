import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vm: PulseBarViewModel
    @EnvironmentObject private var storageVM: StorageViewModel
    @State private var selection: DashboardTab? = .overview
    @State private var now: Date = .now
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Sidebar groups. Settings is intentionally excluded — ⌘, opens the macOS-native
    /// Settings window which is the canonical place for prefs.
    private var performanceTabs: [DashboardTab] { [.overview, .processes, .devServers, .alerts] }
    private var storageTabs: [DashboardTab] { [.storage, .storageHistory] }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section(DashboardTabGroup.performance.title) {
                    ForEach(performanceTabs, id: \.self) { tab in
                        NavigationLink(value: tab) {
                            Label(tab.title, systemImage: tab.symbol)
                        }
                    }
                }
                Section(DashboardTabGroup.storage.title) {
                    ForEach(storageTabs, id: \.self) { tab in
                        NavigationLink(value: tab) {
                            Label(tab.title, systemImage: tab.symbol)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailHeader

                    Group {
                        switch selection {
                        case .overview, .none:
                            OverviewSection(snapshot: vm.snapshot)
                                .environmentObject(vm)
                                .environmentObject(storageVM)
                            StorageOverviewCallout(onShowStorage: { selection = .storage })
                                .environmentObject(storageVM)
                            TopActivitySection(onSeeAll: { selection = .processes })
                                .environmentObject(appState)
                                .environmentObject(vm)
                            AlertsSection(alerts: vm.alerts,
                                          onShowProcesses: { selection = .processes })
                                .environmentObject(vm)
                        case .processes:
                            ProcessesSection()
                                .environmentObject(appState)
                                .environmentObject(vm)
                                .onAppear { vm.filter = .all }
                        case .devServers:
                            ProcessesSection()
                                .environmentObject(appState)
                                .environmentObject(vm)
                                .onAppear { vm.filter = .devServers }
                        case .alerts:
                            AlertsSection(alerts: vm.alerts,
                                          onShowProcesses: { selection = .processes })
                                .environmentObject(vm)
                        case .storage:
                            StorageSection()
                                .environmentObject(storageVM)
                        case .storageHistory:
                            StorageInsightsView()
                                .environmentObject(storageVM)
                                .environmentObject(appState.scanHistoryStore)
                        case .settings:
                            // Reachable only via deep-link; in normal nav this case is unused.
                            SettingsView()
                                .environmentObject(vm)
                        }
                    }
                }
                .padding(24)
            }
            .onReceive(tick) { now = $0 }
            .sheet(item: Binding(
                get: { vm.processPendingKill },
                set: { _ in vm.cancelKill() }
            )) { row in
                KillConfirmDialog(row: row)
                    .environmentObject(appState)
                    .environmentObject(vm)
            }
        }
    }

    // MARK: - Detail header

    private var detailHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(currentTabTitle)
                    .font(.largeTitle.weight(.semibold))
                HStack(spacing: 10) {
                    StatusPill(systemImage: "bolt.horizontal.circle",
                               text: "\(vm.snapshot.runningProcessCount) running")
                    StatusPill(systemImage: "hammer",
                               text: "\(vm.snapshot.devServerCount) dev servers")
                    if !vm.alerts.isEmpty {
                        StatusPill(systemImage: "bell.badge",
                                   text: "\(vm.alerts.count) alert\(vm.alerts.count == 1 ? "" : "s")",
                                   tint: .red)
                    }
                    Text(freshnessLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                vm.refresh(full: true)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("r", modifiers: [.command])
            .help("Refresh now (⌘R)")
        }
    }

    private var currentTabTitle: String {
        switch selection {
        case .overview, .none: return "Overview"
        case .processes: return "Processes"
        case .devServers: return "Dev Servers"
        case .alerts: return "Alerts"
        case .storage: return "Storage"
        case .storageHistory: return "History & Trends"
        case .settings: return "Settings"
        }
    }

    /// Friendly "Updated 3s ago" / "Updated 1m ago" stamp so the user knows the data is fresh.
    private var freshnessLabel: String {
        guard let last = vm.lastFullRefresh else { return "Updating…" }
        let elapsed = Int(now.timeIntervalSince(last))
        if elapsed < 2 { return "Just now" }
        if elapsed < 60 { return "Updated \(elapsed)s ago" }
        return "Updated \(elapsed / 60)m ago"
    }
}

// MARK: - Status pill (compact metric chip in the header)
private struct StatusPill: View {
    let systemImage: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(tint == .red ? Color.red.opacity(0.12) : Color.secondary.opacity(0.10))
        )
    }
}
