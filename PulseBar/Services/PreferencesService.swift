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
        static let refreshIntervalSeconds = "pref.refreshIntervalSeconds"
        static let backgroundSlowdownFactor = "pref.backgroundSlowdownFactor"
        static let heavyCpuPercent = "pref.heavyCpuPercent"      // Int percent — threshold for "Heavy" filter
        static let heavyMemoryGB = "pref.heavyMemoryGB"          // Int GB — memory threshold for "Heavy" filter
        static let alertSoundEnabled = "pref.alertSoundEnabled"  // Bool — play sound with notifications
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
