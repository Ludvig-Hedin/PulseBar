import Foundation
import UserNotifications
import AppKit

/// Posts macOS system notifications for RAM, CPU and battery threshold crossings.
/// The service de-duplicates notifications so the user is never spammed:
/// a given threshold (e.g. RAM 80%) only fires again once usage has dropped
/// below (threshold − hysteresis) and climbed back up, or after `cooldown` elapses.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private var lastFired: [String: Date] = [:]
    private var armed: [String: Bool] = [:]
    private let cooldown: TimeInterval = 15 * 60 // 15 min cooldown per distinct event
    private let hysteresisPercent: Double = 3    // value must drop this far below a threshold to re-arm

    private init() {}

    /// Ask for notification permission. Safe to call repeatedly; the system only prompts once.
    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            self.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    /// Evaluate the latest snapshot against user thresholds and fire/rearm notifications.
    func evaluate(snapshot: SystemSnapshot, topProcess: ProcessRow?) {
        let prefs = PreferencesService.shared
        guard prefs.notificationsEnabled, !prefs.pauseNotifications else { return }

        // RAM thresholds
        let ramPercent = snapshot.memoryTotalBytes > 0
            ? (Double(snapshot.memoryUsedBytes) / Double(snapshot.memoryTotalBytes)) * 100
            : 0
        for threshold in prefs.ramThresholds.sorted() {
            let key = "ram.\(threshold)"
            let crossed = ramPercent >= Double(threshold)
            let rearmBelow = ramPercent < Double(threshold) - hysteresisPercent
            handleThresholdCross(
                key: key,
                crossed: crossed,
                rearmBelow: rearmBelow,
                title: "RAM at \(threshold)%",
                body: topProcess.map { "Top: \($0.name) — \(ByteFormatting.memory($0.memoryBytes))" }
                    ?? String(format: "Memory usage hit %.0f%%", ramPercent),
                level: threshold >= 90 ? .critical : (threshold >= 80 ? .warning : .info)
            )
        }

        // CPU threshold
        let cpuKey = "cpu.\(prefs.cpuThreshold)"
        let cpuCrossed = snapshot.cpuUsagePercent >= Double(prefs.cpuThreshold)
        let cpuRearm = snapshot.cpuUsagePercent < Double(prefs.cpuThreshold) - hysteresisPercent
        handleThresholdCross(
            key: cpuKey,
            crossed: cpuCrossed,
            rearmBelow: cpuRearm,
            title: "CPU at \(prefs.cpuThreshold)%+",
            body: topProcess.map { "Top: \($0.name) — \(Int($0.cpuPercent))%" }
                ?? String(format: "System CPU at %.0f%%", snapshot.cpuUsagePercent),
            level: .warning
        )

        // Battery low
        if let batt = snapshot.batteryPercent, !snapshot.batteryIsCharging {
            let bKey = "battery.\(prefs.batteryThreshold)"
            let bCrossed = batt <= Double(prefs.batteryThreshold)
            let bRearm = batt > Double(prefs.batteryThreshold) + hysteresisPercent
            handleThresholdCross(
                key: bKey,
                crossed: bCrossed,
                rearmBelow: bRearm,
                title: "Battery at \(Int(batt))%",
                body: "Plug in to keep working.",
                level: .warning
            )
        }
    }

    private func handleThresholdCross(key: String, crossed: Bool, rearmBelow: Bool, title: String, body: String, level: AlertItem.Level) {
        let isArmed = armed[key] ?? true
        let lastTime = lastFired[key] ?? .distantPast
        let cooldownElapsed = Date().timeIntervalSince(lastTime) > cooldown

        if crossed, isArmed {
            post(title: title, body: body, level: level)
            lastFired[key] = Date()
            armed[key] = false
        } else if rearmBelow {
            // Drop back below → re-arm so the next cross fires again.
            armed[key] = true
        } else if crossed, cooldownElapsed {
            // Still crossed after cooldown — fire again as a reminder.
            post(title: title, body: body, level: level)
            lastFired[key] = Date()
        }
    }

    private func post(title: String, body: String, level: AlertItem.Level) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if PreferencesService.shared.alertSoundEnabled {
            content.sound = level == .critical ? .defaultCritical : .default
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}
