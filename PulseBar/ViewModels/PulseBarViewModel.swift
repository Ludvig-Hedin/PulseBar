import Foundation
import AppKit
import Combine

@MainActor
final class PulseBarViewModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case devServers = "Dev Servers"
        case heavy = "Heavy"
        case apps = "Apps"
        case cli = "CLI"
        var id: String { rawValue }
    }

    /// Columns the user can sort by. Order here controls the column headers.
    enum SortColumn: String, CaseIterable, Identifiable {
        case name = "Name"
        case ports = "Ports"
        case cpu = "CPU"
        case memory = "Memory"
        case uptime = "Uptime"
        var id: String { rawValue }
    }

    enum SortDirection { case ascending, descending }

    enum VisibleColumn: String, CaseIterable, Identifiable {
        case ports = "Ports"
        case cpu = "CPU"
        case memory = "Memory"
        case uptime = "Uptime"
        var id: String { rawValue }
    }

    // MARK: - Published state
    @Published var snapshot = SystemSnapshot()
    @Published var processes: [ProcessRow] = []
    @Published var alerts: [AlertItem] = []

    @Published var filter: Filter = .all
    @Published var sortColumn: SortColumn = .cpu
    @Published var sortDirection: SortDirection = .descending
    @Published var searchText: String = ""

    @Published var processPendingKill: ProcessRow?
    @Published var isSelectMode: Bool = false
    @Published var selectedProcessPIDs: Set<Int32> = []
    @Published var visibleColumns: Set<VisibleColumn> = [.ports, .cpu, .memory, .uptime]

    /// Wall-clock time of the last full refresh (process enumeration).
    /// Drives the "Updated Xs ago" stamp so the user trusts the data they see.
    @Published private(set) var lastFullRefresh: Date?

    /// Short CPU history (last ~60 samples) for the sparkline. Kept deliberately small.
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var ramHistory: [Double] = []
    private let maxHistory = 60

    // MARK: - Services
    private var metricsService = SystemMetricsService()
    private let processService = ProcessService()
    private let networkService = NetworkService()
    private let batteryService = BatteryService()
    private let alertsService = AlertsService()
    private let killService = KillService()
    private let autoQuitService = AutoQuitService()
    /// Owned by `AppState`. Refreshed once per tick so the Overview disk tile and the
    /// Storage tab share a single, cheap source of truth.
    weak var storageService: StorageService?

    init(storageService: StorageService? = nil) {
        self.storageService = storageService
    }

    // MARK: - Auto-Quit
    /// Most recent events surfaced by the Auto-Quit pipeline. UI binds to this.
    @Published private(set) var autoQuitEvents: [AutoQuitEvent] = []

    // MARK: - Selection state for shift/cmd multi-select
    /// PID of the most recently toggled row, used as the anchor for shift-click range selection.
    @Published var lastSelectedPID: Int32?

    // MARK: - Process view mode
    /// Table vs cards rendering for the Processes view. Persisted to UserDefaults.
    @Published var processViewMode: PreferencesService.ProcessViewMode = PreferencesService.shared.processViewMode {
        didSet { PreferencesService.shared.processViewMode = processViewMode }
    }

    // MARK: - Timing
    private var timer: Timer?
    private var tickCount = 0
    /// Guards against overlapping refresh tasks. Multiple triggers (timer + manual
    /// Refresh button + post-kill `asyncAfter`) can otherwise spawn concurrent refresh
    /// Tasks whose completion order is non-deterministic, letting a stale snapshot land
    /// after a fresher one.
    private var isRefreshing = false
    /// Toggled by the app when no UI is visible — polling slows down drastically.
    var isInBackground: Bool = false {
        didSet { if oldValue != isInBackground { restartTimer() } }
    }
    /// When the user has the main window open we refresh more eagerly.
    var isDashboardVisible: Bool = false {
        didSet { if oldValue != isDashboardVisible { restartTimer() } }
    }

    var menuBarSymbol: String {
        if isCritical {
            return "exclamationmark.triangle.fill"
        }
        if snapshot.cpuUsagePercent > 70 {
            return "gauge.with.dots.needle.67percent"
        }
        return "speedometer"
    }

    /// True when the system is in a state the user should act on immediately.
    /// Drives both icon swap and the menu-bar text color so the signal is louder.
    var isCritical: Bool {
        snapshot.memoryPressure == .critical || snapshot.cpuUsagePercent > 90
    }

    /// Short text shown next to the menu-bar icon. The format is driven by the user's
    /// `menuBarMetricMode` preference:
    ///  • `.auto`  → "CPU 85%" or "MEM 72%" depending on which percentage is currently higher
    ///  • `.cpu`   → "85%"
    ///  • `.ram`   → "72%"
    ///  • `.both`  → "CPU 85%  MEM 72%"
    ///  • `.none`  → "" (icon only)
    var menuBarText: String {
        let mode = PreferencesService.shared.menuBarMetricMode
        let cpu = snapshot.cpuUsagePercent
        let ram = snapshot.memoryUsedPercent
        switch mode {
        case .none:
            return ""
        case .cpu:
            return String(format: "%.0f%%", cpu)
        case .ram:
            return String(format: "%.0f%%", ram)
        case .both:
            return String(format: "CPU %.0f%%  MEM %.0f%%", cpu, ram)
        case .auto:
            // Show whichever metric is harder-loaded right now.
            if ram >= cpu {
                return String(format: "MEM %.0f%%", ram)
            } else {
                return String(format: "CPU %.0f%%", cpu)
            }
        }
    }

    // MARK: - Lifecycle
    func start() {
        NotificationService.shared.requestAuthorizationIfNeeded()
        refresh(full: true)
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        let base = PreferencesService.shared.refreshIntervalSeconds
        let slowdown = PreferencesService.shared.backgroundSlowdownFactor
        // When idle (no window open + menu closed) poll much less often to save power.
        let interval: TimeInterval = isInBackground && !isDashboardVisible
            ? base * slowdown
            : base
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.tickCount += 1
                // Full refresh (process enumeration + lsof) much less frequently.
                let fullEvery = self.isDashboardVisible ? 5 : 15
                let shouldFull = self.tickCount % fullEvery == 0
                self.refresh(full: shouldFull)
            }
        }
    }

    func refresh(full: Bool = false) {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            defer { self.isRefreshing = false }
            let cpu = self.metricsService.cpuUsagePercent()
            let memory = self.metricsService.memoryUsage()
            let battery = self.batteryService.read()
            let network = self.networkService.sampleRate()
            self.storageService?.refreshDiskUsage()

            var running = self.processes
            if full {
                let svc = processService  // capture on MainActor before crossing into detached task
                running = await Task.detached { [svc] in
                    let portMap = ProcessSampling.allListeningPorts()
                    return svc.runningProcesses(portMap: portMap)
                }.value
            }

            let newSnapshot = SystemSnapshot(
                timestamp: .now,
                cpuUsagePercent: cpu,
                memoryUsedBytes: memory.usedBytes,
                memoryTotalBytes: memory.totalBytes,
                memoryPressure: memory.pressure,
                batteryPercent: battery.percent,
                batteryIsCharging: battery.isCharging,
                batteryMinutesRemaining: battery.minutesRemaining,
                networkDownloadBytesPerSecond: network.downloadBytesPerSecond,
                networkUploadBytesPerSecond: network.uploadBytesPerSecond,
                runningProcessCount: running.count,
                devServerCount: running.filter(\.isLikelyDevServer).count
            )

            // Append to history (bounded)
            self.cpuHistory.append(cpu)
            if self.cpuHistory.count > self.maxHistory { self.cpuHistory.removeFirst(self.cpuHistory.count - self.maxHistory) }
            self.ramHistory.append(newSnapshot.memoryUsedPercent)
            if self.ramHistory.count > self.maxHistory { self.ramHistory.removeFirst(self.ramHistory.count - self.maxHistory) }

            self.snapshot = newSnapshot
            if full {
                self.processes = running
                self.lastFullRefresh = .now
                self.alerts = self.alertsService.evaluate(snapshot: newSnapshot, processes: running)
                let activePIDs = Set(running.flatMap(\.sampledPIDs))
                AppIconService.shared.prune(activePIDs: activePIDs)
                ProcessSampling.prune(activePIDs: activePIDs)

                // Evaluate Auto-Quit rules — only on full refresh so we have fresh CPU%/uptime data.
                self.runAutoQuit(processes: running)
            } else {
                // Even on cheap ticks, refresh the alert list so thresholds reflect live CPU/RAM.
                self.alerts = self.alertsService.evaluate(snapshot: newSnapshot, processes: running)
            }

            // Hand off to the notification pipeline regardless of full/partial refresh.
            let topCPU = running.max(by: { $0.cpuPercent < $1.cpuPercent })
            NotificationService.shared.evaluate(snapshot: newSnapshot, topProcess: topCPU)
        }
    }

    // MARK: - Filtering + sorting
    var filteredProcesses: [ProcessRow] {
        let base = processes.filter { row in
            let filterMatch: Bool = {
                switch filter {
                case .all:
                    return true
                case .devServers:
                    return row.isLikelyDevServer
                case .heavy:
                    let cpuThresh = Double(PreferencesService.shared.heavyCpuPercent)
                    let memThresh = UInt64(PreferencesService.shared.heavyMemoryGB) * 1_000_000_000
                    return row.cpuPercent >= cpuThresh || row.memoryBytes >= memThresh
                case .apps:
                    return row.kind == .app
                case .cli:
                    return row.kind == .cli
                }
            }()

            let searchMatch = searchText.isEmpty
                || row.name.localizedCaseInsensitiveContains(searchText)
                || (row.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
                || (row.executablePath?.localizedCaseInsensitiveContains(searchText) ?? false)
                || row.ports.contains { String($0).contains(searchText) }

            return filterMatch && searchMatch
        }

        let sorted: [ProcessRow]
        switch sortColumn {
        case .name:
            sorted = base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .ports:
            sorted = base.sorted { ($0.ports.first ?? .max) < ($1.ports.first ?? .max) }
        case .cpu:
            sorted = base.sorted { $0.cpuPercent < $1.cpuPercent }
        case .memory:
            sorted = base.sorted { $0.memoryBytes < $1.memoryBytes }
        case .uptime:
            // Sort by uptime (seconds since launch), not by launchDate. Ascending = shortest
            // uptime first; descending = longest first. Rows without a launch date sink to the
            // bottom in both directions via a sentinel of -1.
            let now = Date()
            sorted = base.sorted {
                let lhs = $0.launchDate.map { now.timeIntervalSince($0) } ?? -1
                let rhs = $1.launchDate.map { now.timeIntervalSince($0) } ?? -1
                return lhs < rhs
            }
        }
        return sortDirection == .ascending ? sorted : sorted.reversed()
    }

    /// Click handler for column headers — same column toggles direction, new column resets to
    /// its natural default (numbers descending, text ascending).
    func tapSort(_ column: SortColumn) {
        if sortColumn == column {
            sortDirection = (sortDirection == .ascending) ? .descending : .ascending
        } else {
            sortColumn = column
            sortDirection = (column == .name) ? .ascending : .descending
        }
    }

    // MARK: - Kill actions
    func requestKill(_ row: ProcessRow) { processPendingKill = row }
    func cancelKill() { processPendingKill = nil }

    func gracefulQuitSelected() {
        guard let row = processPendingKill else { return }
        _ = killService.gracefulQuit(pid: row.pid)
        processPendingKill = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.refresh() }
    }

    func forceQuitSelected() {
        guard let row = processPendingKill else { return }
        _ = killService.forceQuit(pid: row.pid)
        processPendingKill = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.refresh() }
    }

    // MARK: - Selection
    func toggleSelectMode() {
        isSelectMode.toggle()
        if !isSelectMode {
            selectedProcessPIDs.removeAll()
            lastSelectedPID = nil
        }
    }

    func toggleSelection(_ pid: Int32) {
        if selectedProcessPIDs.contains(pid) {
            selectedProcessPIDs.remove(pid)
        } else {
            selectedProcessPIDs.insert(pid)
        }
        lastSelectedPID = pid
    }

    /// Modifier-aware selection used by checkbox + row clicks.
    /// - shift held → select contiguous range between `lastSelectedPID` and `pid` in the
    ///   currently-visible filtered list. Useful for selecting batches of zombie processes.
    /// - cmd held  → toggle just this row (same as default click).
    /// - no mods   → toggle just this row.
    func selectWithModifiers(pid: Int32, shift: Bool, command: Bool) {
        let ordered = filteredProcesses.map(\.pid)
        if shift, let anchor = lastSelectedPID,
           let a = ordered.firstIndex(of: anchor),
           let b = ordered.firstIndex(of: pid) {
            let (lo, hi) = a <= b ? (a, b) : (b, a)
            for p in ordered[lo...hi] { selectedProcessPIDs.insert(p) }
            // Anchor stays put so the user can extend the selection further.
        } else if command {
            toggleSelection(pid)
        } else {
            toggleSelection(pid)
        }
    }

    func selectAll() {
        selectedProcessPIDs = Set(filteredProcesses.map(\.pid))
    }

    func clearSelection() {
        selectedProcessPIDs.removeAll()
        lastSelectedPID = nil
    }

    /// Force-kills all selected processes, then exits select mode.
    func forceKillSelected() {
        for pid in selectedProcessPIDs {
            _ = killService.forceQuit(pid: pid)
        }
        selectedProcessPIDs.removeAll()
        isSelectMode = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.refresh(full: true) }
    }

    // MARK: - Column visibility
    func isColumnVisible(_ column: VisibleColumn) -> Bool {
        visibleColumns.contains(column)
    }

    func toggleColumnVisibility(_ column: VisibleColumn) {
        if visibleColumns.contains(column) {
            visibleColumns.remove(column)
        } else {
            visibleColumns.insert(column)
        }
    }

    // MARK: - Row actions
    func activateApp(_ row: ProcessRow) {
        guard let app = NSRunningApplication(processIdentifier: row.pid) else { return }
        app.activate(options: [.activateIgnoringOtherApps])
    }

    func revealInFinder(_ row: ProcessRow) {
        guard let path = row.executablePath else { return }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    func copyPID(_ row: ProcessRow) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(String(row.pid), forType: .string)
    }

    // MARK: - Auto-Quit

    /// Runs the user's auto-quit rules. Called only on full refresh ticks so we have
    /// fresh per-process CPU% samples.
    private func runAutoQuit(processes: [ProcessRow]) {
        let prefs = PreferencesService.shared
        guard prefs.autoQuitEnabled else { return }
        let rules = prefs.autoQuitRules
        let fired = autoQuitService.evaluate(rules: rules, processes: processes)
        guard !fired.isEmpty else { return }
        autoQuitEvents = autoQuitService.recentEvents
        if prefs.autoQuitNotify {
            NotificationService.shared.postAutoQuit(events: fired)
        }
    }
}
