import SwiftUI

@main
struct PulseBarApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        // Menu-bar extra: icon + live CPU% label next to it (when enabled).
        MenuBarExtra {
            MenuBarRootView()
                .environmentObject(appState)
                .environmentObject(appState.viewModel)
                .frame(width: 380)
        } label: {
            MenuBarLabel(viewModel: appState.viewModel)
        }
        .menuBarExtraStyle(.window)

        Window("PulseBar", id: "main") {
            MainDashboardView()
                .environmentObject(appState)
                .environmentObject(appState.viewModel)
                .frame(minWidth: 1080, minHeight: 760)
                // When the main window appears/disappears, tell the VM so it can
                // speed up or throttle down its polling cadence.
                .onAppear { appState.viewModel.isDashboardVisible = true }
                .onDisappear { appState.viewModel.isDashboardVisible = false }
        }
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentSize)
        .onChange(of: scenePhase) { _, newPhase in
            // Pause heavy polling when the whole app is inactive / in the background.
            appState.viewModel.isInBackground = (newPhase != .active)
        }

        // Separate Settings scene — invokable via ⌘, and the menu-bar dropdown.
        // Wrapped in a ScrollView so the full-width layout can scroll in the standalone panel.
        Settings {
            ScrollView {
                SettingsView()
                    .environmentObject(appState.viewModel)
                    .padding(24)
            }
            .frame(width: 640, height: 700)
        }
    }
}

/// Renders the menu-bar icon and (optionally) a live CPU% label.
/// Split into its own view so SwiftUI redraws it whenever the VM publishes.
private struct MenuBarLabel: View {
    @ObservedObject var viewModel: PulseBarViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.menuBarSymbol)
            if !viewModel.menuBarText.isEmpty {
                Text(viewModel.menuBarText)
                    .monospacedDigit()
            }
        }
    }
}
