import Foundation
import SwiftUI
import ServiceManagement

/// Centralised user preferences backed by UserDefaults.
/// Exposes @AppStorage-friendly keys as well as a typed singleton accessor.
/// All thresholds and flags live here so the Settings panel and the alert/notification
/// pipeline stay in sync.
@MainActor
final class PreferencesService: ObservableObject {
    static let shared = PreferencesService()

    // MARK: - Keys (kept as constants so AppStorage call sites match)
    enum Key {
        static let notificationsEnabled = "pref.notificationsEnabled"
        static let pauseNotifications = "pref.pauseNotifications"
        static let ramThresholds = "pref.ramThresholds"          // [Int] percent values
        static let cpuThreshold = "pref.cpuThreshold"            // Int percent
        static let batteryThreshold = "pref.batteryThreshold"    // Int percent
        static let launchAtLogin = "pref.launchAtLogin"
        static let showMenuBarCPU = "pref.showMenuBarCPU"
        static let showMenuBarRAM = "pref.showMenuBarRAM"
        static let menuBarMetricMode = "pref.menuBarMetricMode"  // see MenuBarMetricMode
        static let refreshIntervalSeconds = "pref.refreshIntervalSeconds"
        static let backgroundSlowdownFactor = "pref.backgroundSlowdownFactor"
        static let heavyCpuPercent = "pref.heavyCpuPercent"      // Int percent — threshold for "Heavy" filter
        static let heavyMemoryGB = "pref.heavyMemoryGB"          // Int GB — memory threshold for "Heavy" filter
        static let alertSoundEnabled = "pref.alertSoundEnabled"  // Bool — play sound with notifications
        static let autoQuitEnabled = "pref.autoQuitEnabled"      // Bool — master switch for Auto-Quit
        static let autoQuitRules = "pref.autoQuitRules"          // Data — JSON encoded [AutoQuitRule]
        static let autoQuitNotify = "pref.autoQuitNotify"        // Bool — banner when Auto-Quit fires
        static let processViewMode = "pref.processViewMode"      // see ProcessViewMode
        static let notificationProfile = "pref.notificationProfile" // see NotificationProfile
        static let persistentCritical = "pref.persistentCritical"   // Bool — stick around for critical
        static let notificationCooldownMinutes = "pref.notificationCooldownMinutes" // Int — min minutes between any two notifications
    }

    /// How aggressively the app posts threshold notifications.
    /// Each profile bundles a min-level filter, a global cross-channel cooldown,
    /// and the hysteresis required before the same threshold can refire.
    enum NotificationProfile: String, CaseIterable, Identifiable {
        case normal
        case quiet
        case criticalOnly
        var id: String { rawValue }

        var label: String {
            switch self {
            case .normal: return "Normal"
            case .quiet: return "Quiet"
            case .criticalOnly: return "Critical only"
            }
        }

        var description: String {
            switch self {
            case .normal: return "Warning + critical alerts. 5-minute cooldown between any two banners."
            case .quiet: return "Warning + critical alerts, but with a 30-minute cooldown and bigger swings required."
            case .criticalOnly: return "Only critical events (>90% RAM, >95% CPU, near-dead battery)."
            }
        }

        /// Minimum severity that survives the filter for this profile.
        var minLevel: AlertItem.Level {
            switch self {
            case .normal, .quiet: return .warning
            case .criticalOnly: return .critical
            }
        }

        /// Default global cooldown — also overridable by `notificationCooldownMinutes`.
        var defaultCooldownMinutes: Int {
            switch self {
            case .normal: return 5
            case .quiet, .criticalOnly: return 30
            }
        }

        /// Percentage points by which a metric must drop before its threshold re-arms.
        /// Larger numbers prevent the metric from flapping across the threshold and spamming.
        var hysteresisPoints: Double {
            switch self {
            case .normal: return 5
            case .quiet, .criticalOnly: return 12
            }
        }
    }

    /// Menu-bar metric display mode. Replaces the legacy showMenuBarCPU + showMenuBarRAM toggles
    /// while staying backward-compatible (defaults are derived from those flags on first read).
    enum MenuBarMetricMode: String, CaseIterable, Identifiable {
        case auto    // show whichever of CPU/RAM is currently higher %
        case cpu
        case ram
        case both
        case none
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: return "Auto (whichever is higher)"
            case .cpu: return "CPU only"
            case .ram: return "RAM only"
            case .both: return "CPU + RAM"
            case .none: return "Icon only"
            }
        }
    }

    /// How the Processes list is rendered.
    enum ProcessViewMode: String, CaseIterable, Identifiable {
        case table
        case cards
        var id: String { rawValue }
        var label: String {
            switch self {
            case .table: return "Table"
            case .cards: return "Cards"
            }
        }
        var systemImage: String {
            switch self {
            case .table: return "list.bullet"
            case .cards: return "square.grid.2x2"
            }
        }
    }

    // MARK: - Defaults
    static let defaultRamThresholds: [Int] = [50, 70, 80, 90]
    static let defaultCpuThreshold: Int = 85
    static let defaultBatteryThreshold: Int = 20
    static let defaultRefreshInterval: Double = 2.0
    static let defaultBackgroundSlowdownFactor: Double = 5.0
    static let defaultHeavyCpuPercent: Int = 20
    static let defaultHeavyMemoryGB: Int = 1

    private init() {
        let d = UserDefaults.standard
        // Seed defaults on first run so the Settings panel reflects them.
        if d.object(forKey: Key.notificationsEnabled) == nil { d.set(true, forKey: Key.notificationsEnabled) }
        if d.object(forKey: Key.ramThresholds) == nil { d.set(Self.defaultRamThresholds, forKey: Key.ramThresholds) }
        if d.object(forKey: Key.cpuThreshold) == nil { d.set(Self.defaultCpuThreshold, forKey: Key.cpuThreshold) }
        if d.object(forKey: Key.batteryThreshold) == nil { d.set(Self.defaultBatteryThreshold, forKey: Key.batteryThreshold) }
        if d.object(forKey: Key.showMenuBarCPU) == nil { d.set(true, forKey: Key.showMenuBarCPU) }
        if d.object(forKey: Key.showMenuBarRAM) == nil { d.set(false, forKey: Key.showMenuBarRAM) }
        if d.object(forKey: Key.refreshIntervalSeconds) == nil { d.set(Self.defaultRefreshInterval, forKey: Key.refreshIntervalSeconds) }
        if d.object(forKey: Key.backgroundSlowdownFactor) == nil { d.set(Self.defaultBackgroundSlowdownFactor, forKey: Key.backgroundSlowdownFactor) }
        if d.object(forKey: Key.heavyCpuPercent) == nil { d.set(Self.defaultHeavyCpuPercent, forKey: Key.heavyCpuPercent) }
        if d.object(forKey: Key.heavyMemoryGB) == nil { d.set(Self.defaultHeavyMemoryGB, forKey: Key.heavyMemoryGB) }
        if d.object(forKey: Key.alertSoundEnabled) == nil { d.set(true, forKey: Key.alertSoundEnabled) }
        if d.object(forKey: Key.autoQuitEnabled) == nil { d.set(false, forKey: Key.autoQuitEnabled) }
        if d.object(forKey: Key.autoQuitNotify) == nil { d.set(true, forKey: Key.autoQuitNotify) }
        if d.object(forKey: Key.notificationProfile) == nil {
            d.set(NotificationProfile.normal.rawValue, forKey: Key.notificationProfile)
        }
        if d.object(forKey: Key.persistentCritical) == nil { d.set(true, forKey: Key.persistentCritical) }
        // 0 = "use profile default". Lets the user opt in to a custom cooldown without
        // having to manage state when switching profiles.
        if d.object(forKey: Key.notificationCooldownMinutes) == nil { d.set(0, forKey: Key.notificationCooldownMinutes) }

        // Backfill menu-bar metric mode from legacy CPU/RAM toggles so existing users don't
        // lose their pref on upgrade.
        if d.object(forKey: Key.menuBarMetricMode) == nil {
            let showCPU = d.bool(forKey: Key.showMenuBarCPU)
            let showRAM = d.bool(forKey: Key.showMenuBarRAM)
            let derived: MenuBarMetricMode
            if showCPU && showRAM { derived = .both }
            else if showRAM { derived = .ram }
            else if showCPU { derived = .cpu }
            else { derived = .none }
            d.set(derived.rawValue, forKey: Key.menuBarMetricMode)
        }
        if d.object(forKey: Key.processViewMode) == nil {
            d.set(ProcessViewMode.table.rawValue, forKey: Key.processViewMode)
        }
    }

    // MARK: - Typed accessors (read-only convenience used from services)
    var notificationsEnabled: Bool { UserDefaults.standard.bool(forKey: Key.notificationsEnabled) }
    var pauseNotifications: Bool { UserDefaults.standard.bool(forKey: Key.pauseNotifications) }
    var ramThresholds: [Int] {
        (UserDefaults.standard.array(forKey: Key.ramThresholds) as? [Int]) ?? Self.defaultRamThresholds
    }
    var cpuThreshold: Int {
        let v = UserDefaults.standard.integer(forKey: Key.cpuThreshold)
        return v > 0 ? v : Self.defaultCpuThreshold
    }
    var batteryThreshold: Int {
        let v = UserDefaults.standard.integer(forKey: Key.batteryThreshold)
        return v > 0 ? v : Self.defaultBatteryThreshold
    }
    var showMenuBarCPU: Bool { UserDefaults.standard.bool(forKey: Key.showMenuBarCPU) }
    var showMenuBarRAM: Bool { UserDefaults.standard.bool(forKey: Key.showMenuBarRAM) }
    var heavyCpuPercent: Int {
        let v = UserDefaults.standard.integer(forKey: Key.heavyCpuPercent)
        return v > 0 ? v : Self.defaultHeavyCpuPercent
    }
    var heavyMemoryGB: Int {
        let v = UserDefaults.standard.integer(forKey: Key.heavyMemoryGB)
        return v > 0 ? v : Self.defaultHeavyMemoryGB
    }
    var alertSoundEnabled: Bool { UserDefaults.standard.bool(forKey: Key.alertSoundEnabled) }
    var refreshIntervalSeconds: Double {
        let v = UserDefaults.standard.double(forKey: Key.refreshIntervalSeconds)
        return v > 0 ? v : Self.defaultRefreshInterval
    }
    var backgroundSlowdownFactor: Double {
        let v = UserDefaults.standard.double(forKey: Key.backgroundSlowdownFactor)
        return v > 0 ? v : Self.defaultBackgroundSlowdownFactor
    }
    var menuBarMetricMode: MenuBarMetricMode {
        get {
            let raw = UserDefaults.standard.string(forKey: Key.menuBarMetricMode) ?? MenuBarMetricMode.auto.rawValue
            return MenuBarMetricMode(rawValue: raw) ?? .auto
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.menuBarMetricMode) }
    }
    var processViewMode: ProcessViewMode {
        get {
            let raw = UserDefaults.standard.string(forKey: Key.processViewMode) ?? ProcessViewMode.table.rawValue
            return ProcessViewMode(rawValue: raw) ?? .table
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.processViewMode) }
    }

    // MARK: - Auto-Quit

    var autoQuitEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.autoQuitEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Key.autoQuitEnabled) }
    }

    var autoQuitNotify: Bool {
        get { UserDefaults.standard.bool(forKey: Key.autoQuitNotify) }
        set { UserDefaults.standard.set(newValue, forKey: Key.autoQuitNotify) }
    }

    var autoQuitRules: [AutoQuitRule] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Key.autoQuitRules) else { return [] }
            return (try? JSONDecoder().decode([AutoQuitRule].self, from: data)) ?? []
        }
        set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data()
            UserDefaults.standard.set(data, forKey: Key.autoQuitRules)
        }
    }

    // MARK: - Notification anti-spam

    var notificationProfile: NotificationProfile {
        get {
            let raw = UserDefaults.standard.string(forKey: Key.notificationProfile) ?? NotificationProfile.normal.rawValue
            return NotificationProfile(rawValue: raw) ?? .normal
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.notificationProfile) }
    }

    /// Critical alerts stay around longer when this is on (timeSensitive interruption level
    /// + stable identifier so they coalesce in Notification Center instead of stacking).
    var persistentCritical: Bool {
        get { UserDefaults.standard.bool(forKey: Key.persistentCritical) }
        set { UserDefaults.standard.set(newValue, forKey: Key.persistentCritical) }
    }

    /// 0 = "use profile default". Anything else is a user-specified override (minutes).
    var notificationCooldownMinutes: Int {
        get { UserDefaults.standard.integer(forKey: Key.notificationCooldownMinutes) }
        set { UserDefaults.standard.set(newValue, forKey: Key.notificationCooldownMinutes) }
    }

    /// Effective cooldown (in seconds), accounting for the override.
    var effectiveCooldownSeconds: TimeInterval {
        let override = notificationCooldownMinutes
        let minutes = override > 0 ? override : notificationProfile.defaultCooldownMinutes
        return TimeInterval(minutes * 60)
    }

    // MARK: - Launch at login
    /// Wraps SMAppService for macOS 13+. Returns true on success.
    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                UserDefaults.standard.set(enabled, forKey: Key.launchAtLogin)
                return true
            } catch {
                // Silently fail — surfaced via the Settings UI.
                return false
            }
        }
        return false
    }

    var launchAtLogin: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
}
