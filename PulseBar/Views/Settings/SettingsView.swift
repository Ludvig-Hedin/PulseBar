import SwiftUI

/// The app's preferences panel — full-width desktop layout embedded in the dashboard
/// (or standalone via ⌘,). All values backed by @AppStorage / UserDefaults so changes
/// take effect immediately across the menu-bar UI and notification pipeline.
struct SettingsView: View {
    @EnvironmentObject private var vm: PulseBarViewModel

    // MARK: - Notification prefs
    @AppStorage(PreferencesService.Key.notificationsEnabled) private var notificationsEnabled: Bool = true
    @AppStorage(PreferencesService.Key.pauseNotifications)   private var pauseNotifications: Bool = false
    @AppStorage(PreferencesService.Key.cpuThreshold)         private var cpuThreshold: Int = PreferencesService.defaultCpuThreshold
    @AppStorage(PreferencesService.Key.batteryThreshold)     private var batteryThreshold: Int = PreferencesService.defaultBatteryThreshold
    @AppStorage(PreferencesService.Key.alertSoundEnabled)    private var alertSoundEnabled: Bool = true

    // MARK: - Menu bar prefs
    @AppStorage(PreferencesService.Key.showMenuBarCPU) private var showMenuBarCPU: Bool = true
    @AppStorage(PreferencesService.Key.showMenuBarRAM) private var showMenuBarRAM: Bool = false

    // MARK: - Process prefs
    @AppStorage(PreferencesService.Key.heavyCpuPercent) private var heavyCpuPercent: Int = PreferencesService.defaultHeavyCpuPercent
    @AppStorage(PreferencesService.Key.heavyMemoryGB)   private var heavyMemoryGB: Int = PreferencesService.defaultHeavyMemoryGB

    // MARK: - Performance prefs
    @AppStorage(PreferencesService.Key.refreshIntervalSeconds)   private var refreshIntervalSeconds: Double = PreferencesService.defaultRefreshInterval
    @AppStorage(PreferencesService.Key.backgroundSlowdownFactor) private var backgroundSlowdownFactor: Double = PreferencesService.defaultBackgroundSlowdownFactor

    // MARK: - Startup (non-AppStorage — uses SMAppService)
    @State private var launchAtLogin: Bool = PreferencesService.shared.launchAtLogin

    // MARK: - RAM threshold checkboxes
    @State private var ram50 = PreferencesService.shared.ramThresholds.contains(50)
    @State private var ram70 = PreferencesService.shared.ramThresholds.contains(70)
    @State private var ram80 = PreferencesService.shared.ramThresholds.contains(80)
    @State private var ram90 = PreferencesService.shared.ramThresholds.contains(90)

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            // ── Notifications ──────────────────────────────────────────────
            settingsCard(title: "Notifications", systemImage: "bell.badge.fill", color: .red) {
                // On/off + DND
                settingsRow("Enable notifications") {
                    Toggle("", isOn: $notificationsEnabled).labelsHidden()
                }
                rowDivider()
                settingsRow("Do not disturb") {
                    Toggle("", isOn: $pauseNotifications).labelsHidden()
                        .disabled(!notificationsEnabled)
                }
                rowDivider()
                settingsRow("Play sound with alerts") {
                    Toggle("", isOn: $alertSoundEnabled).labelsHidden()
                        .disabled(!notificationsEnabled)
                }

                rowDivider()

                // RAM thresholds
                VStack(alignment: .leading, spacing: 8) {
                    Text("RAM alert thresholds")
                        .font(.system(size: 13))
                    HStack(spacing: 20) {
                        Toggle("50%", isOn: $ram50)
                        Toggle("70%", isOn: $ram70)
                        Toggle("80%", isOn: $ram80)
                        Toggle("90%", isOn: $ram90)
                        Spacer()
                    }
                    .toggleStyle(.checkbox)
                    .disabled(!notificationsEnabled)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .onChange(of: ram50) { _, _ in persistRamThresholds() }
                .onChange(of: ram70) { _, _ in persistRamThresholds() }
                .onChange(of: ram80) { _, _ in persistRamThresholds() }
                .onChange(of: ram90) { _, _ in persistRamThresholds() }

                rowDivider()

                // CPU threshold
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CPU alert threshold")
                            .font(.system(size: 13))
                        Text("Alert when total CPU usage reaches this level")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Stepper(
                        value: $cpuThreshold,
                        in: 40...100,
                        step: 5,
                        label: {
                            Text("\(cpuThreshold)%")
                                .monospacedDigit()
                                .frame(minWidth: 40, alignment: .trailing)
                        }
                    )
                    .disabled(!notificationsEnabled)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                rowDivider()

                // Battery threshold
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Battery alert threshold")
                            .font(.system(size: 13))
                        Text("Alert when battery drops below this level (unplugged)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Stepper(
                        value: $batteryThreshold,
                        in: 5...50,
                        step: 5,
                        label: {
                            Text("\(batteryThreshold)%")
                                .monospacedDigit()
                                .frame(minWidth: 40, alignment: .trailing)
                        }
                    )
                    .disabled(!notificationsEnabled)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            // ── Two-column row: Menu Bar + Processes ───────────────────────
            HStack(alignment: .top, spacing: 20) {

                // Menu Bar
                settingsCard(title: "Menu Bar", systemImage: "menubar.rectangle", color: .blue) {
                    settingsRow("Show CPU%") {
                        Toggle("", isOn: $showMenuBarCPU).labelsHidden()
                    }
                    rowDivider()
                    settingsRow("Show RAM%") {
                        Toggle("", isOn: $showMenuBarRAM).labelsHidden()
                    }
                }
                .frame(maxWidth: .infinity)

                // Processes
                settingsCard(title: "Processes", systemImage: "gearshape.2.fill", color: .purple) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\"Heavy\" CPU threshold")
                                .font(.system(size: 13))
                            Text("Processes at or above this CPU usage are flagged")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Stepper(
                            value: $heavyCpuPercent,
                            in: 5...95,
                            step: 5,
                            label: {
                                Text("\(heavyCpuPercent)%")
                                    .monospacedDigit()
                                    .frame(minWidth: 40, alignment: .trailing)
                            }
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    rowDivider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\"Heavy\" memory threshold")
                                .font(.system(size: 13))
                            Text("Processes using this much RAM or more are flagged")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Stepper(
                            value: $heavyMemoryGB,
                            in: 1...32,
                            step: 1,
                            label: {
                                Text("\(heavyMemoryGB) GB")
                                    .monospacedDigit()
                                    .frame(minWidth: 44, alignment: .trailing)
                            }
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .frame(maxWidth: .infinity)
            }

            // ── Two-column row: Performance + Startup ─────────────────────
            HStack(alignment: .top, spacing: 20) {

                // Performance
                settingsCard(title: "Performance", systemImage: "speedometer", color: .orange) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Active refresh interval")
                                .font(.system(size: 13))
                            Spacer()
                            Text(String(format: "%.1fs", refreshIntervalSeconds))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .font(.system(size: 13))
                        }
                        Slider(value: $refreshIntervalSeconds, in: 1...5, step: 0.5)
                        Text("How often metrics update when the dashboard or menu is open")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    rowDivider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Background slowdown")
                                .font(.system(size: 13))
                            Spacer()
                            Text(String(format: "×%.0f", backgroundSlowdownFactor))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .font(.system(size: 13))
                        }
                        Slider(value: $backgroundSlowdownFactor, in: 1...10, step: 1)
                        Text("When no UI is visible, polling rate is divided by this factor to save battery")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .frame(maxWidth: .infinity)

                // Startup
                VStack(spacing: 20) {
                    settingsCard(title: "Startup", systemImage: "power.circle.fill", color: .green) {
                        settingsRow(
                            "Launch PulseBar at login",
                            description: "Start monitoring automatically when you log in"
                        ) {
                            Toggle("", isOn: Binding(
                                get: { launchAtLogin },
                                set: { newValue in
                                    if PreferencesService.shared.setLaunchAtLogin(newValue) {
                                        launchAtLogin = newValue
                                    }
                                }
                            ))
                            .labelsHidden()
                        }
                    }

                    // Restore defaults — lives in this column so the layout stays balanced
                    HStack {
                        Button("Restore Defaults") { restoreDefaults() }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.bottom, 8)

            // Card body
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.09), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func settingsRow<Control: View>(
        _ label: String,
        description: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func rowDivider() -> some View {
        Divider()
            .padding(.leading, 14)
    }

    // MARK: - Persistence helpers

    private func persistRamThresholds() {
        var list: [Int] = []
        if ram50 { list.append(50) }
        if ram70 { list.append(70) }
        if ram80 { list.append(80) }
        if ram90 { list.append(90) }
        UserDefaults.standard.set(list, forKey: PreferencesService.Key.ramThresholds)
    }

    private func restoreDefaults() {
        notificationsEnabled = true
        pauseNotifications = false
        alertSoundEnabled = true
        cpuThreshold = PreferencesService.defaultCpuThreshold
        batteryThreshold = PreferencesService.defaultBatteryThreshold
        showMenuBarCPU = true
        showMenuBarRAM = false
        heavyCpuPercent = PreferencesService.defaultHeavyCpuPercent
        heavyMemoryGB = PreferencesService.defaultHeavyMemoryGB
        refreshIntervalSeconds = PreferencesService.defaultRefreshInterval
        backgroundSlowdownFactor = PreferencesService.defaultBackgroundSlowdownFactor
        ram50 = true; ram70 = true; ram80 = true; ram90 = true
        persistRamThresholds()
    }
}
