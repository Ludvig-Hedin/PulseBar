import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vm: PulseBarViewModel
    @State private var selection: DashboardTab? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Views") {
                    ForEach([DashboardTab.overview, .processes, .devServers, .alerts, .settings], id: \.self) { tab in
                        NavigationLink(value: tab) {
                            Label(tab.title, systemImage: tab.symbol)
                        }
                    }
                }

                Section("Quick status") {
                    Label("\(vm.snapshot.runningProcessCount) running", systemImage: "bolt.horizontal.circle")
                    Label("\(vm.snapshot.devServerCount) dev servers", systemImage: "hammer")
                    if vm.alerts.count > 0 {
                        Label("\(vm.alerts.count) alerts", systemImage: "bell.badge")
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.sidebar)
            .tint(.secondary)
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PulseBar")
                                .font(.largeTitle.weight(.bold))
                            Text("Fast overview. Detailed view when you need it.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            vm.refresh(full: true)
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("r", modifiers: [.command])
                    }

                    Group {
                        switch selection {
                        case .overview, .none:
                            OverviewSection(snapshot: vm.snapshot)
                                .environmentObject(vm)
                            AlertsSection(alerts: vm.alerts)
                            ProcessesSection()
                                .environmentObject(appState)
                                .environmentObject(vm)
                                .onAppear { vm.filter = .all }
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
                            AlertsSection(alerts: vm.alerts)
                        case .settings:
                            SettingsView()
                                .environmentObject(vm)
                        }
                    }
                }
                .padding(24)
            }
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
}
