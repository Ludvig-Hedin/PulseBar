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

    // MARK: - Timing
    private var timer: Timer?
    private var tickCount = 0
    /// Toggled by the app when no UI is visible — polling slows down drastically.
    var isInBackground: Bool = false {
        didSet { if oldValue != isInBackground { restartTimer() } }
    }
    /// When the user has the main window open we refresh more eagerly.
    var isDashboardVisible: Bool = false {
        didSet { if oldValue != isDashboardVisible { restartTimer() } }
    }

    var menuBarSymbol: String {
        if snapshot.memoryPressure == .critical || snapshot.cpuUsagePercent > 90 {
            return "exclamationmark.triangle.fill"
        }
        if snapshot.cpuUsagePercent > 70 {
            return "gauge.with.dots.needle.67percent"
        }
        return "speedometer"
    }

    /// Short text shown next to the menu-bar icon based on enabled metrics.
    /// Single metric: bare "85%" format. Both enabled: prefixed "CPU 85%  MEM 72%".
    var menuBarText: String {
        let prefs = PreferencesService.shared
        let showCPU = prefs.showMenuBarCPU
        let showRAM = prefs.showMenuBarRAM
        let multi = showCPU && showRAM
        var parts: [String] = []
        if showCPU {
            parts.append(multi
                ? String(format: "CPU %.0f%%", snapshot.cpuUsagePercent)
                : String(format: "%.0f%%", snapshot.cpuUsagePercent))
        }
        if showRAM {
            parts.append(multi
                ? String(format: "MEM %.0f%%", snapshot.memoryUsedPercent)
                : String(format: "%.0f%%", snapshot.memoryUsedPercent))
        }
        return parts.joined(separator: "  ")
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
        Task {
            let cpu = self.metricsService.cpuUsagePercent()
            let memory = self.metricsService.memoryUsage()
            let battery = self.batteryService.read()
            let network = self.networkService.sampleRate()

            var running = self.processes
            if full {
                running = await Task.detached {
                    let portMap = ProcessSampling.allListeningPorts()
                    return self.processService.runningProcesses(portMap: portMap)
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
                self.alerts = self.alertsService.evaluate(snapshot: newSnapshot, processes: running)
                AppIconService.shared.prune(activePIDs: Set(running.map(\.pid)))
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
            sorted = base.sorted { ($0.launchDate ?? .distantFuture) < ($1.launchDate ?? .distantFuture) }
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
        if !isSelectMode { selectedProcessPIDs.removeAll() }
    }

    func toggleSelection(_ pid: Int32) {
        if selectedProcessPIDs.contains(pid) {
            selectedProcessPIDs.remove(pid)
        } else {
            selectedProcessPIDs.insert(pid)
        }
    }

    func selectAll() {
        selectedProcessPIDs = Set(filteredProcesses.map(\.pid))
    }

    func clearSelection() {
        selectedProcessPIDs.removeAll()
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
}
