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
    @AppStorage(PreferencesService.Key.notificationProfile)  private var notificationProfileRaw: String = PreferencesService.NotificationProfile.normal.rawValue
    @AppStorage(PreferencesService.Key.persistentCritical)   private var persistentCritical: Bool = true
    @AppStorage(PreferencesService.Key.notificationCooldownMinutes) private var notificationCooldownMinutes: Int = 0

    // MARK: - Menu bar prefs
    @AppStorage(PreferencesService.Key.menuBarMetricMode) private var menuBarMetricModeRaw: String = PreferencesService.MenuBarMetricMode.auto.rawValue

    // MARK: - Auto-Quit prefs
    @AppStorage(PreferencesService.Key.autoQuitEnabled) private var autoQuitEnabled: Bool = false
    @AppStorage(PreferencesService.Key.autoQuitNotify)  private var autoQuitNotify: Bool = true
    @State private var autoQuitRules: [AutoQuitRule] = PreferencesService.shared.autoQuitRules
    @State private var editingRule: AutoQuitRule?
    @State private var showingNewRule: Bool = false

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

    // MARK: - UI state
    @State private var showRestoreConfirm = false

    private var notificationsActive: Bool { notificationsEnabled && !pauseNotifications }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            // ── Notifications ──────────────────────────────────────────────
            settingsCard(title: "Notifications", systemImage: "bell.badge.fill", color: .red) {
                settingsRow("Enable notifications") {
                    Toggle("", isOn: $notificationsEnabled).labelsHidden()
                }
                rowDivider()
                settingsRow("Do not disturb",
                            description: "Mute all notifications without changing your thresholds",
                            disabled: !notificationsEnabled) {
                    Toggle("", isOn: $pauseNotifications).labelsHidden()
                        .disabled(!notificationsEnabled)
                }
                rowDivider()

                // Spam controls — profile bundles the cooldown + sensitivity in one knob.
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Notification volume")
                            .font(.system(size: 13))
                        Spacer()
                        Picker("", selection: $notificationProfileRaw) {
                            ForEach(PreferencesService.NotificationProfile.allCases) { profile in
                                Text(profile.label).tag(profile.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                        .onChange(of: notificationProfileRaw) { _, _ in
                            NotificationService.shared.resetSpamState()
                        }
                    }
                    Text(profileDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .opacity(notificationsActive ? 1 : 0.5)
                .disabled(!notificationsActive)

                rowDivider()

                stepperRow(
                    title: "Minimum gap between banners",
                    description: "0 uses the profile default. Larger values silence the same metric for longer.",
                    value: $notificationCooldownMinutes,
                    range: 0...120,
                    step: 5,
                    suffix: " min",
                    disabled: !notificationsActive
                )

                rowDivider()

                settingsRow("Keep critical alerts visible",
                            description: "Critical alerts pierce Focus modes and stay around in Notification Center",
                            disabled: !notificationsActive) {
                    Toggle("", isOn: $persistentCritical).labelsHidden()
                        .disabled(!notificationsActive)
                }

                rowDivider()

                settingsRow("Play sound with alerts",
                            disabled: !notificationsActive) {
                    Toggle("", isOn: $alertSoundEnabled).labelsHidden()
                        .disabled(!notificationsActive)
                }

                rowDivider()

                // RAM thresholds
                VStack(alignment: .leading, spacing: 6) {
                    Text("RAM alert thresholds")
                        .font(.system(size: 13))
                    Text("Each level fires its own notification — turn off the ones you don't want.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 20) {
                        Toggle("50%", isOn: $ram50)
                        Toggle("70%", isOn: $ram70)
                        Toggle("80%", isOn: $ram80)
                        Toggle("90%", isOn: $ram90)
                        Spacer()
                    }
                    .toggleStyle(.checkbox)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .opacity(notificationsActive ? 1 : 0.5)
                .disabled(!notificationsActive)
                .onChange(of: ram50) { _, _ in persistRamThresholds() }
                .onChange(of: ram70) { _, _ in persistRamThresholds() }
                .onChange(of: ram80) { _, _ in persistRamThresholds() }
                .onChange(of: ram90) { _, _ in persistRamThresholds() }

                rowDivider()

                stepperRow(
                    title: "CPU alert threshold",
                    description: "Alert when total CPU usage reaches this level",
                    value: $cpuThreshold,
                    range: 40...100,
                    step: 5,
                    suffix: "%",
                    disabled: !notificationsActive
                )

                rowDivider()

                stepperRow(
                    title: "Battery alert threshold",
                    description: "Alert when battery drops below this level (unplugged)",
                    value: $batteryThreshold,
                    range: 5...50,
                    step: 5,
                    suffix: "%",
                    disabled: !notificationsActive
                )
            }

            // ── Two-column row: Menu Bar + Processes ───────────────────────
            HStack(alignment: .top, spacing: 20) {

                // Menu Bar
                settingsCard(title: "Menu Bar", systemImage: "menubar.rectangle", color: .blue) {
                    settingsRow("Metric next to icon",
                                description: "Auto picks whichever of CPU or RAM is using more right now") {
                        Picker("", selection: $menuBarMetricModeRaw) {
                            ForEach(PreferencesService.MenuBarMetricMode.allCases) { mode in
                                Text(mode.label).tag(mode.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 220)
                    }
                }
                .frame(maxWidth: .infinity)

                // Processes
                settingsCard(title: "Processes", systemImage: "gearshape.2.fill", color: .purple) {
                    stepperRow(
                        title: "\u{201C}Heavy\u{201D} CPU threshold",
                        description: "Processes at or above this CPU usage appear in the Heavy filter",
                        value: $heavyCpuPercent,
                        range: 5...95,
                        step: 5,
                        suffix: "%"
                    )

                    rowDivider()

                    stepperRow(
                        title: "\u{201C}Heavy\u{201D} memory threshold",
                        description: "Processes using this much RAM or more appear in the Heavy filter",
                        value: $heavyMemoryGB,
                        range: 1...32,
                        step: 1,
                        suffix: " GB"
                    )
                }
                .frame(maxWidth: .infinity)
            }

            // ── Two-column row: Performance + Startup ─────────────────────
            HStack(alignment: .top, spacing: 20) {

                // Performance
                settingsCard(title: "Performance", systemImage: "speedometer", color: .orange) {
                    sliderRow(
                        title: "Active refresh interval",
                        description: "How often metrics update while the dashboard or menu is open",
                        value: $refreshIntervalSeconds,
                        range: 1...5,
                        step: 0.5,
                        formatter: { String(format: "%.1fs", $0) }
                    )

                    rowDivider()

                    sliderRow(
                        title: "Background slowdown",
                        description: "When no UI is visible, polling rate is divided by this factor to save battery",
                        value: $backgroundSlowdownFactor,
                        range: 1...10,
                        step: 1,
                        formatter: { String(format: "×%.0f", $0) }
                    )
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

                    HStack {
                        Button("Restore Defaults") { showRestoreConfirm = true }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .help("Reset every setting to its default value")
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // ── Auto-Quit ──────────────────────────────────────────────────
            autoQuitCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $editingRule, onDismiss: { autoQuitRules = PreferencesService.shared.autoQuitRules }) { rule in
            AutoQuitRuleEditor(rule: rule) { updated in
                upsertRule(updated)
            }
        }
        .sheet(isPresented: $showingNewRule, onDismiss: { autoQuitRules = PreferencesService.shared.autoQuitRules }) {
            AutoQuitRuleEditor(rule: AutoQuitRule(name: "New rule", nameContains: "")) { created in
                upsertRule(created)
            }
        }
        .confirmationDialog(
            "Reset every setting to defaults?",
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore Defaults", role: .destructive) { restoreDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your custom thresholds and preferences will be replaced with the originals.")
        }
    }

    // MARK: - Row helpers

    @ViewBuilder
    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.bottom, 8)

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
        disabled: Bool = false,
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
        .opacity(disabled ? 0.5 : 1)
    }

    @ViewBuilder
    private func stepperRow(
        title: String,
        description: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        suffix: String,
        disabled: Bool = false
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Stepper(
                value: value,
                in: range,
                step: step,
                label: {
                    Text("\(value.wrappedValue)\(suffix)")
                        .monospacedDigit()
                        .frame(minWidth: 44, alignment: .trailing)
                }
            )
            .disabled(disabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(disabled ? 0.5 : 1)
    }

    @ViewBuilder
    private func sliderRow(
        title: String,
        description: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        formatter: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                Text(formatter(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
            }
            Slider(value: value, in: range, step: step)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
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
        menuBarMetricModeRaw = PreferencesService.MenuBarMetricMode.auto.rawValue
        heavyCpuPercent = PreferencesService.defaultHeavyCpuPercent
        heavyMemoryGB = PreferencesService.defaultHeavyMemoryGB
        refreshIntervalSeconds = PreferencesService.defaultRefreshInterval
        backgroundSlowdownFactor = PreferencesService.defaultBackgroundSlowdownFactor
        autoQuitEnabled = false
        autoQuitNotify = true
        notificationProfileRaw = PreferencesService.NotificationProfile.normal.rawValue
        persistentCritical = true
        notificationCooldownMinutes = 0
        ram50 = true; ram70 = true; ram80 = true; ram90 = true
        persistRamThresholds()
        NotificationService.shared.resetSpamState()
    }

    /// Human-readable description for the currently-selected notification profile.
    /// Drives the helper text shown below the segmented picker.
    private var profileDescription: String {
        let profile = PreferencesService.NotificationProfile(rawValue: notificationProfileRaw) ?? .normal
        return profile.description
    }

    // MARK: - Auto-Quit card

    @ViewBuilder
    private var autoQuitCard: some View {
        settingsCard(title: "Auto-Quit",
                     systemImage: "bolt.slash.fill",
                     color: .pink) {
            settingsRow("Enable Auto-Quit",
                        description: "Automatically quit processes that match a rule below") {
                Toggle("", isOn: $autoQuitEnabled).labelsHidden()
            }
            rowDivider()
            settingsRow("Notify when a process is quit",
                        disabled: !autoQuitEnabled) {
                Toggle("", isOn: $autoQuitNotify).labelsHidden()
                    .disabled(!autoQuitEnabled)
            }
            rowDivider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Rules")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button {
                        showingNewRule = true
                    } label: {
                        Label("Add rule", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!autoQuitEnabled)
                }

                if autoQuitRules.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No rules yet.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Button("Add zombie node/bun preset") {
                            upsertRule(.zombieNodeBunPreset)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Quits node/bun processes that have run for 5+ minutes and use ≥50% CPU")
                        .disabled(!autoQuitEnabled)
                    }
                } else {
                    VStack(spacing: 6) {
                        ForEach(autoQuitRules) { rule in
                            AutoQuitRuleRow(rule: rule,
                                            onEdit: { editingRule = rule },
                                            onToggle: { newValue in
                                                var r = rule
                                                r.enabled = newValue
                                                upsertRule(r)
                                            },
                                            onDelete: { deleteRule(rule) })
                                .opacity(autoQuitEnabled ? 1 : 0.5)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if !vm.autoQuitEvents.isEmpty {
                rowDivider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent kills")
                        .font(.system(size: 13, weight: .semibold))
                    ForEach(vm.autoQuitEvents.suffix(5).reversed()) { event in
                        AutoQuitEventRow(event: event)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Rule mutation

    private func upsertRule(_ rule: AutoQuitRule) {
        var list = PreferencesService.shared.autoQuitRules
        if let idx = list.firstIndex(where: { $0.id == rule.id }) {
            list[idx] = rule
        } else {
            list.append(rule)
        }
        PreferencesService.shared.autoQuitRules = list
        autoQuitRules = list
    }

    private func deleteRule(_ rule: AutoQuitRule) {
        var list = PreferencesService.shared.autoQuitRules
        list.removeAll { $0.id == rule.id }
        PreferencesService.shared.autoQuitRules = list
        autoQuitRules = list
    }
}

// MARK: - Rule row

private struct AutoQuitRuleRow: View {
    let rule: AutoQuitRule
    var onEdit: () -> Void
    var onToggle: (Bool) -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { rule.enabled }, set: onToggle))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.system(size: 13, weight: .medium))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Edit", action: onEdit)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Delete rule")
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var summary: String {
        var parts: [String] = []
        if !rule.nameContains.isEmpty { parts.append("name ~ “\(rule.nameContains)”") }
        if !rule.pathContains.isEmpty { parts.append("path ~ “\(rule.pathContains)”") }
        if rule.minCpuPercent > 0 { parts.append("CPU ≥ \(Int(rule.minCpuPercent))%") }
        if rule.minMemoryMB > 0 { parts.append("RAM ≥ \(Int(rule.minMemoryMB)) MB") }
        if rule.minUptimeSeconds > 0 { parts.append("alive ≥ \(rule.minUptimeSeconds)s") }
        parts.append("sustained \(rule.sustainedSeconds)s")
        parts.append(rule.force ? "force quit" : "graceful quit")
        return parts.joined(separator: " · ")
    }
}

private struct AutoQuitEventRow: View {
    let event: AutoQuitEvent
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption)
            Text(event.processName)
                .font(.caption.weight(.medium))
            Text("·")
                .foregroundStyle(.secondary)
            Text("by \(event.ruleName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(event.timestamp, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    private var icon: String {
        switch event.action {
        case .graceful: return "bolt.slash"
        case .force: return "xmark.octagon.fill"
        case .skipped: return "shield"
        }
    }
    private var color: Color {
        switch event.action {
        case .graceful: return .pink
        case .force: return .red
        case .skipped: return .orange
        }
    }
}
