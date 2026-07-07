import Foundation
import UserNotifications
import AppKit

/// Posts macOS system notifications for RAM, CPU and battery threshold crossings.
///
/// Anti-spam contract:
///  • Per-key cooldown enforced after every fire (rearm + flap can't bypass it).
///  • Cross-channel throttle prevents a CPU + RAM + battery burst from arriving at once.
///  • Hysteresis sized by user's `NotificationProfile` so small wiggles don't refire.
///  • Min-severity filter respects the user's profile (e.g. `criticalOnly`).
///  • Stable per-key identifiers — reposting an event replaces the prior banner in
///    Notification Center instead of stacking copies.
///  • Critical alerts may opt in to `.timeSensitive` interruption level so they
///    pierce Focus and remain visible longer.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    /// Per-key state. Keeping this in-memory is fine — daemon restarts reset the user's
    /// notification expectations anyway, and the cooldown applies on the next tick regardless.
    private struct ChannelState {
        var lastFiredAt: Date = .distantPast
        var armed: Bool = true
    }
    private var channels: [String: ChannelState] = [:]

    /// Cross-channel global throttle so multiple metrics crossing at the same tick don't
    /// fire as a synchronized burst. 30s is enough to space distinct events out without
    /// hiding genuinely separate alarms.
    private var globalLastFireAt: Date = .distantPast
    private let globalMinGap: TimeInterval = 30

    private init() {}

    /// Ask for notification permission. Safe to call repeatedly; the system only prompts once.
    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            guard settings.authorizationStatus == .notDetermined else { return }
            Task { @MainActor in
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }
    }

    /// Evaluate the latest snapshot against user thresholds and fire/rearm notifications.
    func evaluate(snapshot: SystemSnapshot, topProcess: ProcessRow?) {
        let prefs = PreferencesService.shared
        guard prefs.notificationsEnabled, !prefs.pauseNotifications else { return }

        let profile = prefs.notificationProfile
        let hysteresis = profile.hysteresisPoints
        let cooldown = prefs.effectiveCooldownSeconds

        // RAM — fire only the highest crossed threshold so a 95% spike doesn't post
        // one banner per configured tier.
        let ramPercent = snapshot.memoryTotalBytes > 0
            ? (Double(snapshot.memoryUsedBytes) / Double(snapshot.memoryTotalBytes)) * 100
            : 0
        let sortedRamThresholds = prefs.ramThresholds.sorted()
        let highestCrossedRam = sortedRamThresholds.last { ramPercent >= Double($0) }
        for threshold in sortedRamThresholds {
            let key = "ram.\(threshold)"
            let isHighestCrossed = (threshold == highestCrossedRam)
            let rearmBelow = ramPercent < Double(threshold) - hysteresis
            handleThresholdCross(
                key: key,
                crossed: isHighestCrossed,
                rearmBelow: rearmBelow,
                title: "RAM at \(threshold)%",
                body: topProcess.map { "Top: \($0.name) — \(ByteFormatting.memory($0.memoryBytes))" }
                    ?? String(format: "Memory usage hit %.0f%%", ramPercent),
                level: threshold >= 90 ? .critical : (threshold >= 80 ? .warning : .info),
                cooldown: cooldown
            )
        }

        // CPU
        handleThresholdCross(
            key: "cpu.\(prefs.cpuThreshold)",
            crossed: snapshot.cpuUsagePercent >= Double(prefs.cpuThreshold),
            rearmBelow: snapshot.cpuUsagePercent < Double(prefs.cpuThreshold) - hysteresis,
            title: "CPU at \(prefs.cpuThreshold)%+",
            body: topProcess.map { "Top: \($0.name) — \(Int($0.cpuPercent))%" }
                ?? String(format: "System CPU at %.0f%%", snapshot.cpuUsagePercent),
            level: snapshot.cpuUsagePercent >= 95 ? .critical : .warning,
            cooldown: cooldown
        )

        // Battery low
        if let batt = snapshot.batteryPercent, !snapshot.batteryIsCharging {
            handleThresholdCross(
                key: "battery.\(prefs.batteryThreshold)",
                crossed: batt <= Double(prefs.batteryThreshold),
                rearmBelow: batt > Double(prefs.batteryThreshold) + hysteresis,
                title: "Battery at \(Int(batt))%",
                body: "Plug in to keep working.",
                level: batt <= 10 ? .critical : .warning,
                cooldown: cooldown
            )
        }
    }

    // MARK: - Core firing

    private func handleThresholdCross(
        key: String,
        crossed: Bool,
        rearmBelow: Bool,
        title: String,
        body: String,
        level: AlertItem.Level,
        cooldown: TimeInterval
    ) {
        let profile = PreferencesService.shared.notificationProfile

        // Profile min-level filter — quiet profiles drop warnings entirely.
        if !levelPasses(level, minLevel: profile.minLevel) {
            // Still rearm so when the profile relaxes we don't double-fire.
            if rearmBelow { channels[key, default: .init()].armed = true }
            return
        }

        var state = channels[key, default: .init()]
        let now = Date()
        let cooldownElapsed = now.timeIntervalSince(state.lastFiredAt) >= cooldown
        let globalReady = now.timeIntervalSince(globalLastFireAt) >= globalMinGap

        // Re-arm path — independent of fire path so we always track recovery.
        if rearmBelow {
            state.armed = true
            channels[key] = state
        }

        guard crossed else { return }

        if state.armed, cooldownElapsed, globalReady {
            post(key: key, title: title, body: body, level: level)
            state.lastFiredAt = now
            state.armed = false
            channels[key] = state
            globalLastFireAt = now
        } else if !state.armed, cooldownElapsed, globalReady {
            // Still crossed long after the initial fire — emit a periodic reminder
            // (uses the same identifier so it replaces the prior banner).
            post(key: key, title: title, body: body, level: level)
            state.lastFiredAt = now
            channels[key] = state
            globalLastFireAt = now
        }
    }

    private func levelPasses(_ level: AlertItem.Level, minLevel: AlertItem.Level) -> Bool {
        rank(level) >= rank(minLevel)
    }
    private func rank(_ level: AlertItem.Level) -> Int {
        switch level {
        case .info: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    // MARK: - Posting

    private func post(key: String, title: String, body: String, level: AlertItem.Level) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if PreferencesService.shared.alertSoundEnabled {
            content.sound = level == .critical ? .defaultCritical : .default
        }
        if #available(macOS 12.0, *) {
            // Critical alerts get .timeSensitive when the user wants them persistent —
            // pierces Focus modes and stays visible longer on screen.
            if level == .critical && PreferencesService.shared.persistentCritical {
                content.interruptionLevel = .timeSensitive
            }
        }
        // Stable identifier per channel: re-fires replace the existing entry in
        // Notification Center instead of stacking copies.
        let identifier = "pulsebar.\(key)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        // Remove any pending duplicate first so the new banner pops cleanly.
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.add(request)
    }

    /// Banner summarising one or more Auto-Quit kills. Caller is responsible for honoring
    /// the user's autoQuitNotify preference. Coalesces multiple events into a single banner
    /// so a sweep that kills five processes is one notification, not five.
    func postAutoQuit(events: [AutoQuitEvent]) {
        let killed = events.filter { $0.action != .skipped }
        guard !killed.isEmpty else { return }

        // Respect the same global throttle so Auto-Quit can't out-shout itself.
        let now = Date()
        guard now.timeIntervalSince(globalLastFireAt) >= globalMinGap else { return }

        let title: String
        let body: String
        if killed.count == 1, let one = killed.first {
            title = "Auto-Quit: \(one.processName)"
            body = "Triggered by rule \u{201C}\(one.ruleName)\u{201D}."
        } else {
            title = "Auto-Quit: \(killed.count) processes"
            let names = killed.prefix(3).map(\.processName).joined(separator: ", ")
            let suffix = killed.count > 3 ? "…" : ""
            body = "Quit: \(names)\(suffix)"
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if PreferencesService.shared.alertSoundEnabled {
            content.sound = .default
        }
        let identifier = "pulsebar.autoquit"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.add(request)
        globalLastFireAt = now
    }

    /// User-facing reset — wipes per-channel state so the next evaluation can refire.
    /// Used by Settings when the user switches profiles, so they immediately see the new
    /// behavior instead of having to wait for cooldowns to roll over.
    func resetSpamState() {
        channels.removeAll()
        globalLastFireAt = .distantPast
    }
}
