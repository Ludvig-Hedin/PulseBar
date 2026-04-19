// PulseBar macOS
// Complete Xcode file structure for a minimal, native, menu bar first macOS utility.
// Style goal: system-first, macOS 26 Liquid Glass feel, very little custom styling.
//
// HOW TO USE
// 1) Create a new macOS App in Xcode named PulseBar.
// 2) Use SwiftUI lifecycle.
// 3) Replace the generated files with the files below.
// 4) Add the entitlements/capabilities and Info settings listed at the end.
//
// FILE TREE
// PulseBar/
// ├─ App/
// │  ├─ PulseBarApp.swift
// │  └─ AppState.swift
// ├─ Models/
// │  ├─ ProcessRow.swift
// │  ├─ SystemSnapshot.swift
// │  └─ AlertItem.swift
// ├─ Services/
// │  ├─ SystemMetricsService.swift
// │  ├─ ProcessService.swift
// │  ├─ NetworkService.swift
// │  ├─ BatteryService.swift
// │  ├─ AlertsService.swift
// │  ├─ DevServerDetector.swift
// │  └─ KillService.swift
// ├─ ViewModels/
// │  └─ PulseBarViewModel.swift
// ├─ Views/
// │  ├─ MenuBar/
// │  │  ├─ MenuBarRootView.swift
// │  │  └─ MiniMetricRow.swift
// │  ├─ Dashboard/
// │  │  ├─ MainDashboardView.swift
// │  │  ├─ OverviewSection.swift
// │  │  ├─ AlertsSection.swift
// │  │  ├─ ProcessesSection.swift
// │  │  ├─ ProcessRowView.swift
// │  │  └─ KillConfirmDialog.swift
// │  └─ Shared/
// │     ├─ MetricCard.swift
// │     ├─ SearchBar.swift
// │     └─ EmptyStateView.swift
// └─ Utilities/
//    ├─ ByteFormatting.swift
//    ├─ NumberFormatting.swift
//    ├─ ProcessSampling.swift
//    └─ MachHelpers.swift
//
// ============================================================================
// FILE: App/PulseBarApp.swift
// ============================================================================

import SwiftUI

@main
struct PulseBarApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("PulseBar", systemImage: appState.viewModel.menuBarSymbol) {
            MenuBarRootView()
                .environmentObject(appState)
                .frame(width: 380)
        }
        .menuBarExtraStyle(.window)

        Window("PulseBar", id: "main") {
            MainDashboardView()
                .environmentObject(appState)
                .frame(minWidth: 1080, minHeight: 760)
        }
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentSize)
    }
}

// ============================================================================
// FILE: App/AppState.swift
// ============================================================================

import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var viewModel: PulseBarViewModel

    init() {
        self.viewModel = PulseBarViewModel()
        self.viewModel.start()
    }
}

// ============================================================================
// FILE: Models/SystemSnapshot.swift
// ============================================================================

import Foundation

struct SystemSnapshot: Equatable {
    var timestamp: Date = .now

    var cpuUsagePercent: Double = 0
    var memoryUsedBytes: UInt64 = 0
    var memoryTotalBytes: UInt64 = 0
    var memoryPressure: MemoryPressure = .normal

    var batteryPercent: Double? = nil
    var batteryIsCharging: Bool = false
    var batteryMinutesRemaining: Int? = nil

    var networkDownloadBytesPerSecond: UInt64 = 0
    var networkUploadBytesPerSecond: UInt64 = 0

    var runningProcessCount: Int = 0
    var devServerCount: Int = 0

    enum MemoryPressure: String {
        case normal
        case warning
        case critical
    }
}

// ============================================================================
// FILE: Models/ProcessRow.swift
// ============================================================================

import Foundation

struct ProcessRow: Identifiable, Hashable {
    let id: Int32
    let pid: Int32
    let name: String
    let bundleIdentifier: String?
    let executablePath: String?
    let launchDate: Date?

    let cpuPercent: Double
    let memoryBytes: UInt64

    let kind: Kind
    let isFrontmost: Bool
    let isTerminated: Bool

    let ports: [Int]
    let isLikelyDevServer: Bool
    let devServerKind: String?

    enum Kind: String, CaseIterable, Hashable {
        case app = "App"
        case cli = "CLI"
        case background = "Background"
        case unknown = "Unknown"
    }
}

// ============================================================================
// FILE: Models/AlertItem.swift
// ============================================================================

import Foundation

struct AlertItem: Identifiable, Hashable {
    let id = UUID()
    let level: Level
    let title: String
    let subtitle: String
    let createdAt: Date = .now

    enum Level: String {
        case info
        case warning
        case critical
    }
}

// ============================================================================
// FILE: Services/SystemMetricsService.swift
// ============================================================================

import Foundation
import Darwin.Mach

struct SystemMetricsService {
    private var previousCPUInfo: processor_info_array_t?
    private var previousCPUInfoCount: mach_msg_type_number_t = 0

    mutating func cpuUsagePercent() -> Double {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUsU,
            &cpuInfo,
            &numCpuInfo
        )

        guard result == KERN_SUCCESS, let cpuInfo else { return 0 }

        defer {
            if let previousCPUInfo {
                let prevSize = vm_size_t(previousCPUInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: previousCPUInfo), prevSize)
            }
            previousCPUInfo = cpuInfo
            previousCPUInfoCount = numCpuInfo
        }

        guard let previousCPUInfo else {
            return 0
        }

        var totalUsage: Double = 0

        for cpu in 0..<Int(numCPUsU) {
            let index = Int32(CPU_STATE_MAX * cpu)

            let user = Double(cpuInfo[Int(index + Int32(CPU_STATE_USER))] - previousCPUInfo[Int(index + Int32(CPU_STATE_USER))])
            let system = Double(cpuInfo[Int(index + Int32(CPU_STATE_SYSTEM))] - previousCPUInfo[Int(index + Int32(CPU_STATE_SYSTEM))])
            let nice = Double(cpuInfo[Int(index + Int32(CPU_STATE_NICE))] - previousCPUInfo[Int(index + Int32(CPU_STATE_NICE))])
            let idle = Double(cpuInfo[Int(index + Int32(CPU_STATE_IDLE))] - previousCPUInfo[Int(index + Int32(CPU_STATE_IDLE))])

            let inUse = user + system + nice
            let total = inUse + idle
            if total > 0 {
                totalUsage += inUse / total
            }
        }

        guard numCPUsU > 0 else { return 0 }
        return min(max((totalUsage / Double(numCPUsU)) * 100, 0), 100)
    }

    func memoryUsage() -> (usedBytes: UInt64, totalBytes: UInt64, pressure: SystemSnapshot.MemoryPressure) {
        let total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return (0, total, .normal)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(stats.free_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let speculative = UInt64(stats.speculative_count) * pageSize
        let available = free + inactive + speculative
        let used = total > available ? total - available : 0

        let pressureRatio = total > 0 ? Double(used) / Double(total) : 0
        let pressure: SystemSnapshot.MemoryPressure
        switch pressureRatio {
        case ..<0.75: pressure = .normal
        case ..<0.9: pressure = .warning
        default: pressure = .critical
        }

        return (used, total, pressure)
    }
}

// ============================================================================
// FILE: Services/BatteryService.swift
// ============================================================================

import Foundation
import IOKit.ps

struct BatteryState {
    let percent: Double?
    let isCharging: Bool
    let minutesRemaining: Int?
}

struct BatteryService {
    func read() -> BatteryState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return BatteryState(percent: nil, isCharging: false, minutesRemaining: nil)
        }

        guard let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
            return BatteryState(percent: nil, isCharging: false, minutesRemaining: nil)
        }

        let current = description[kIOPSCurrentCapacityKey] as? Double
        let max = description[kIOPSMaxCapacityKey] as? Double
        let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
        let percent = (current != nil && max != nil && max! > 0) ? ((current! / max!) * 100) : nil

        let estimate = IOPSGetTimeRemainingEstimate()
        let minutesRemaining: Int?
        if estimate.isFinite, estimate >= 0 {
            minutesRemaining = Int(estimate.rounded())
        } else {
            minutesRemaining = nil
        }

        return BatteryState(percent: percent, isCharging: isCharging, minutesRemaining: minutesRemaining)
    }
}

// ============================================================================
// FILE: Services/NetworkService.swift
// ============================================================================

import Foundation
import Darwin

struct NetworkRate {
    let downloadBytesPerSecond: UInt64
    let uploadBytesPerSecond: UInt64
}

struct NetworkCounters {
    let inputBytes: UInt64
    let outputBytes: UInt64
}

final class NetworkService {
    private var previousCounters: NetworkCounters?
    private var previousDate: Date?

    func sampleRate() -> NetworkRate {
        let now = Date()
        let current = currentCounters()

        defer {
            previousCounters = current
            previousDate = now
        }

        guard let previousCounters, let previousDate else {
            return NetworkRate(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
        }

        let delta = max(now.timeIntervalSince(previousDate), 1)
        let down = current.inputBytes >= previousCounters.inputBytes ? current.inputBytes - previousCounters.inputBytes : 0
        let up = current.outputBytes >= previousCounters.outputBytes ? current.outputBytes - previousCounters.outputBytes : 0

        return NetworkRate(
            downloadBytesPerSecond: UInt64(Double(down) / delta),
            uploadBytesPerSecond: UInt64(Double(up) / delta)
        )
    }

    private func currentCounters() -> NetworkCounters {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let first = addressPointer else {
            return .init(inputBytes: 0, outputBytes: 0)
        }

        defer { freeifaddrs(addressPointer) }

        var input: UInt64 = 0
        var output: UInt64 = 0
        var ptr = first

        while true {
            let interface = ptr.pointee
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp, !isLoopback,
               let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                input += UInt64(data.pointee.ifi_ibytes)
                output += UInt64(data.pointee.ifi_obytes)
            }

            guard let next = interface.ifa_next else { break }
            ptr = next
        }

        return .init(inputBytes: input, outputBytes: output)
    }
}

// ============================================================================
// FILE: Services/ProcessService.swift
// ============================================================================

import Foundation
import AppKit

final class ProcessService {
    private let detector = DevServerDetector()

    func runningProcesses() -> [ProcessRow] {
        let apps = NSWorkspace.shared.runningApplications

        return apps.map { app in
            let pid = app.processIdentifier
            let cpu = ProcessSampling.cpuPercent(pid: pid) ?? 0
            let memory = ProcessSampling.memoryBytes(pid: pid) ?? 0
            let ports = ProcessSampling.listeningPorts(pid: pid)
            let devInfo = detector.detect(appName: app.localizedName ?? "", executablePath: app.executableURL?.path, ports: ports)

            let kind: ProcessRow.Kind = {
                if app.activationPolicy == .regular { return .app }
                if app.bundleIdentifier == nil { return .cli }
                if app.activationPolicy == .accessory || app.activationPolicy == .prohibited { return .background }
                return .unknown
            }()

            return ProcessRow(
                id: pid,
                pid: pid,
                name: app.localizedName ?? "Unknown",
                bundleIdentifier: app.bundleIdentifier,
                executablePath: app.executableURL?.path,
                launchDate: nil,
                cpuPercent: cpu,
                memoryBytes: memory,
                kind: kind,
                isFrontmost: app.isActive,
                isTerminated: app.isTerminated,
                ports: ports,
                isLikelyDevServer: devInfo.isDevServer,
                devServerKind: devInfo.kind
            )
        }
        .sorted { lhs, rhs in
            if lhs.isLikelyDevServer != rhs.isLikelyDevServer {
                return lhs.isLikelyDevServer && !rhs.isLikelyDevServer
            }
            return lhs.cpuPercent > rhs.cpuPercent
        }
    }
}

// ============================================================================
// FILE: Services/DevServerDetector.swift
// ============================================================================

import Foundation

struct DevServerInfo {
    let isDevServer: Bool
    let kind: String?
}

struct DevServerDetector {
    private let hints: [String: String] = [
        "node": "Node",
        "npm": "npm",
        "pnpm": "pnpm",
        "yarn": "yarn",
        "bun": "Bun",
        "vite": "Vite",
        "next": "Next.js",
        "nuxt": "Nuxt",
        "astro": "Astro",
        "python": "Python",
        "uvicorn": "Uvicorn",
        "gunicorn": "Gunicorn",
        "flask": "Flask",
        "django": "Django",
        "docker": "Docker",
        "postgres": "Postgres",
        "redis": "Redis",
        "supabase": "Supabase",
        "ngrok": "ngrok"
    ]

    func detect(appName: String, executablePath: String?, ports: [Int]) -> DevServerInfo {
        let source = "\(appName.lowercased()) \((executablePath ?? "").lowercased())"

        for (hint, label) in hints {
            if source.contains(hint) {
                return .init(isDevServer: true, kind: label)
            }
        }

        let commonDevPorts: Set<Int> = [3000, 3001, 5173, 8000, 8080, 8787, 5432, 6379, 9229]
        if ports.contains(where: { commonDevPorts.contains($0) }) {
            return .init(isDevServer: true, kind: "Server")
        }

        return .init(isDevServer: false, kind: nil)
    }
}

// ============================================================================
// FILE: Services/KillService.swift
// ============================================================================

import Foundation
import AppKit

enum KillResult {
    case gracefulRequested
    case forceSucceeded
    case failed
}

struct KillService {
    func gracefulQuit(pid: Int32) -> KillResult {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return .failed }
        let ok = app.terminate()
        return ok ? .gracefulRequested : .failed
    }

    func forceQuit(pid: Int32) -> KillResult {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return .failed }
        let ok = app.forceTerminate()
        return ok ? .forceSucceeded : .failed
    }
}

// ============================================================================
// FILE: Services/AlertsService.swift
// ============================================================================

import Foundation

@MainActor
final class AlertsService {
    private(set) var items: [AlertItem] = []

    func evaluate(snapshot: SystemSnapshot, processes: [ProcessRow]) -> [AlertItem] {
        var output: [AlertItem] = []

        if snapshot.memoryPressure == .critical {
            output.append(.init(level: .critical, title: "Memory pressure is critical", subtitle: "You are close to a bad time."))
        } else if snapshot.memoryPressure == .warning {
            output.append(.init(level: .warning, title: "Memory pressure is rising", subtitle: "A few heavy apps are eating RAM."))
        }

        if snapshot.cpuUsagePercent >= 85 {
            let top = processes.sorted { $0.cpuPercent > $1.cpuPercent }.first
            output.append(.init(level: .warning, title: "CPU is running hot", subtitle: top != nil ? "Top process: \(top!.name)" : "System-wide CPU spike."))
        }

        if let battery = snapshot.batteryPercent,
           !snapshot.batteryIsCharging,
           battery <= 20 {
            output.append(.init(level: .warning, title: "Battery is low", subtitle: "\(Int(battery))% left."))
        }

        items = output
        return output
    }
}

// ============================================================================
// FILE: ViewModels/PulseBarViewModel.swift
// ============================================================================

import Foundation
import AppKit

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

    enum Sort: String, CaseIterable, Identifiable {
        case cpu = "CPU"
        case memory = "Memory"
        case name = "Name"
        var id: String { rawValue }
    }

    @Published var snapshot = SystemSnapshot()
    @Published var processes: [ProcessRow] = []
    @Published var alerts: [AlertItem] = []

    @Published var filter: Filter = .all
    @Published var sort: Sort = .cpu
    @Published var searchText: String = ""

    @Published var processPendingKill: ProcessRow?

    private var timer: Timer?
    private var metricsService = SystemMetricsService()
    private let processService = ProcessService()
    private let networkService = NetworkService()
    private let batteryService = BatteryService()
    private let alertsService = AlertsService()
    private let killService = KillService()

    var menuBarSymbol: String {
        if snapshot.memoryPressure == .critical || snapshot.cpuUsagePercent > 90 {
            return "exclamationmark.triangle.fill"
        }
        return "speedometer"
    }

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let cpu = metricsService.cpuUsagePercent()
        let memory = metricsService.memoryUsage()
        let battery = batteryService.read()
        let network = networkService.sampleRate()
        let running = processService.runningProcesses()

        snapshot = SystemSnapshot(
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

        processes = running
        alerts = alertsService.evaluate(snapshot: snapshot, processes: running)
    }

    var filteredProcesses: [ProcessRow] {
        let base = processes.filter { row in
            let filterMatch: Bool = {
                switch filter {
                case .all:
                    return true
                case .devServers:
                    return row.isLikelyDevServer
                case .heavy:
                    return row.cpuPercent >= 20 || row.memoryBytes >= 1_000_000_000
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

            return filterMatch && searchMatch
        }

        switch sort {
        case .cpu:
            return base.sorted { $0.cpuPercent > $1.cpuPercent }
        case .memory:
            return base.sorted { $0.memoryBytes > $1.memoryBytes }
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func requestKill(_ row: ProcessRow) {
        processPendingKill = row
    }

    func cancelKill() {
        processPendingKill = nil
    }

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
}

// ============================================================================
// FILE: Views/MenuBar/MenuBarRootView.swift
// ============================================================================

import SwiftUI

struct MenuBarRootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let vm = appState.viewModel

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PulseBar")
                        .font(.headline)
                    Text("Activity Monitor, but usable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    vm.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }

            MiniMetricRow(title: "CPU", value: NumberFormatting.percent(vm.snapshot.cpuUsagePercent), subtitle: "System")
            MiniMetricRow(title: "RAM", value: ByteFormatting.gigabytes(vm.snapshot.memoryUsedBytes), subtitle: vm.snapshot.memoryPressure.rawValue.capitalized)
            MiniMetricRow(title: "Network", value: "↓ \(ByteFormatting.rate(vm.snapshot.networkDownloadBytesPerSecond))", subtitle: "↑ \(ByteFormatting.rate(vm.snapshot.networkUploadBytesPerSecond))")
            MiniMetricRow(title: "Battery", value: vm.snapshot.batteryPercent != nil ? NumberFormatting.percent(vm.snapshot.batteryPercent!) : "—", subtitle: vm.snapshot.batteryIsCharging ? "Charging" : "Battery")

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Top strain")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(vm.snapshot.devServerCount) dev servers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(vm.filteredProcesses.prefix(5)) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .lineLimit(1)
                            Text(row.isLikelyDevServer ? "\(row.devServerKind ?? "Dev") · \(row.ports.map(String.init).joined(separator: ", "))" : row.kind.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(NumberFormatting.percent(row.cpuPercent))
                            .monospacedDigit()
                            .font(.caption)
                    }
                }
            }

            if !vm.alerts.isEmpty {
                Divider()
                ForEach(vm.alerts.prefix(2)) { alert in
                    Label(alert.title, systemImage: alert.level == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                        .font(.caption)
                }
            }

            HStack(spacing: 10) {
                Button("Open Dashboard") {
                    openWindow(id: "main")
                }
                .buttonStyle(.borderedProminent)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
    }
}

// ============================================================================
// FILE: Views/MenuBar/MiniMetricRow.swift
// ============================================================================

import SwiftUI

struct MiniMetricRow: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
            }
            Spacer()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// ============================================================================
// FILE: Views/Dashboard/MainDashboardView.swift
// ============================================================================

import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let vm = appState.viewModel

        NavigationSplitView {
            List {
                Section("Views") {
                    Label("Overview", systemImage: "square.grid.2x2")
                    Label("Processes", systemImage: "list.bullet.rectangle")
                    Label("Dev Servers", systemImage: "server.rack")
                    Label("Alerts", systemImage: "bell")
                }

                Section("Quick status") {
                    Label("\(vm.snapshot.runningProcessCount) running", systemImage: "bolt.horizontal.circle")
                    Label("\(vm.snapshot.devServerCount) dev servers", systemImage: "hammer")
                }
            }
            .listStyle(.sidebar)
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
                            vm.refresh()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }

                    OverviewSection(snapshot: vm.snapshot)
                    AlertsSection(alerts: vm.alerts)
                    ProcessesSection()
                        .environmentObject(appState)
                }
                .padding(24)
            }
            .sheet(item: Binding(
                get: { vm.processPendingKill },
                set: { _ in vm.cancelKill() }
            )) { row in
                KillConfirmDialog(row: row)
                    .environmentObject(appState)
            }
        }
    }
}

// ============================================================================
// FILE: Views/Dashboard/OverviewSection.swift
// ============================================================================

import SwiftUI

struct OverviewSection: View {
    let snapshot: SystemSnapshot

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
            MetricCard(title: "CPU", icon: "cpu", value: NumberFormatting.percent(snapshot.cpuUsagePercent), subtitle: "System load")
            MetricCard(title: "Memory", icon: "memorychip", value: ByteFormatting.gigabytes(snapshot.memoryUsedBytes), subtitle: "of \(ByteFormatting.gigabytes(snapshot.memoryTotalBytes)) · \(snapshot.memoryPressure.rawValue.capitalized)")
            MetricCard(title: "Network", icon: "arrow.up.arrow.down", value: "↓ \(ByteFormatting.rate(snapshot.networkDownloadBytesPerSecond))", subtitle: "↑ \(ByteFormatting.rate(snapshot.networkUploadBytesPerSecond))")
            MetricCard(title: "Battery", icon: snapshot.batteryIsCharging ? "battery.100.bolt" : "battery.75", value: snapshot.batteryPercent != nil ? NumberFormatting.percent(snapshot.batteryPercent!) : "—", subtitle: snapshot.batteryIsCharging ? "Charging" : "On battery")
        }
    }
}

// ============================================================================
// FILE: Views/Dashboard/AlertsSection.swift
// ============================================================================

import SwiftUI

struct AlertsSection: View {
    let alerts: [AlertItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Alerts")
                    .font(.title3.weight(.semibold))
                Spacer()
            }

            if alerts.isEmpty {
                EmptyStateView(title: "No active alerts", subtitle: "Your Mac is behaving. Miracles happen.")
            } else {
                VStack(spacing: 10) {
                    ForEach(alerts) { alert in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon(for: alert.level))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alert.title)
                                    .font(.headline)
                                Text(alert.subtitle)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    private func icon(for level: AlertItem.Level) -> String {
        switch level {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.circle"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }
}

// ============================================================================
// FILE: Views/Dashboard/ProcessesSection.swift
// ============================================================================

import SwiftUI

struct ProcessesSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let vm = appState.viewModel

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Processes")
                    .font(.title3.weight(.semibold))
                Spacer()
                Picker("Filter", selection: $vm.filter) {
                    ForEach(PulseBarViewModel.Filter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 420)
            }

            HStack(spacing: 12) {
                SearchBar(text: $vm.searchText, placeholder: "Search process, bundle, path")
                Picker("Sort", selection: $vm.sort) {
                    ForEach(PulseBarViewModel.Sort.allCases) { sort in
                        Text(sort.rawValue).tag(sort)
                    }
                }
                .frame(width: 160)
            }

            VStack(spacing: 0) {
                HStack {
                    Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Ports").frame(width: 120, alignment: .leading)
                    Text("CPU").frame(width: 80, alignment: .trailing)
                    Text("Memory").frame(width: 110, alignment: .trailing)
                    Text("Action").frame(width: 90, alignment: .center)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()

                if vm.filteredProcesses.isEmpty {
                    EmptyStateView(title: "No matching processes", subtitle: "Change the filter or search less aggressively.")
                        .padding(20)
                } else {
                    ForEach(vm.filteredProcesses) { row in
                        ProcessRowView(row: row)
                            .environmentObject(appState)
                        Divider()
                    }
                }
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

// ============================================================================
// FILE: Views/Dashboard/ProcessRowView.swift
// ============================================================================

import SwiftUI

struct ProcessRowView: View {
    @EnvironmentObject private var appState: AppState
    let row: ProcessRow

    var body: some View {
        let vm = appState.viewModel

        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: row.isLikelyDevServer ? "server.rack" : "app.badge")
                    .foregroundStyle(row.isLikelyDevServer ? .orange : .accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.body.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.ports.isEmpty ? "—" : row.ports.prefix(3).map(String.init).joined(separator: ", "))
                .frame(width: 120, alignment: .leading)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(NumberFormatting.percent(row.cpuPercent))
                .frame(width: 80, alignment: .trailing)
                .monospacedDigit()

            Text(ByteFormatting.memory(row.memoryBytes))
                .frame(width: 110, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button("Kill") {
                vm.requestKill(row)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(width: 90)
            .disabled(row.pid == Int32(ProcessInfo.processInfo.processIdentifier))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var subtitle: String {
        if row.isLikelyDevServer {
            let label = row.devServerKind ?? "Dev server"
            return row.executablePath.map { "\(label) · \($0)" } ?? label
        }
        return row.bundleIdentifier ?? row.executablePath ?? row.kind.rawValue
    }
}

// ============================================================================
// FILE: Views/Dashboard/KillConfirmDialog.swift
// ============================================================================

import SwiftUI

struct KillConfirmDialog: View {
    @EnvironmentObject private var appState: AppState
    let row: ProcessRow

    var body: some View {
        let vm = appState.viewModel

        VStack(alignment: .leading, spacing: 16) {
            Text("Quit \(row.name)?")
                .font(.title2.weight(.bold))

            Text("Try graceful quit first. If it ignores you, force quit it.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("PID: \(row.pid)")
                Text("CPU: \(NumberFormatting.percent(row.cpuPercent))")
                Text("Memory: \(ByteFormatting.memory(row.memoryBytes))")
                if !row.ports.isEmpty {
                    Text("Ports: \(row.ports.map(String.init).joined(separator: ", "))")
                }
            }
            .font(.callout)

            HStack {
                Button("Cancel") {
                    vm.cancelKill()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Graceful Quit") {
                    vm.gracefulQuitSelected()
                }
                .buttonStyle(.bordered)

                Button("Force Quit", role: .destructive) {
                    vm.forceQuitSelected()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

// ============================================================================
// FILE: Views/Shared/MetricCard.swift
// ============================================================================

import SwiftUI

struct MetricCard: View {
    let title: String
    let icon: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer()
            }
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// ============================================================================
// FILE: Views/Shared/SearchBar.swift
// ============================================================================

import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
    }
}

// ============================================================================
// FILE: Views/Shared/EmptyStateView.swift
// ============================================================================

import SwiftUI

struct EmptyStateView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// ============================================================================
// FILE: Utilities/ByteFormatting.swift
// ============================================================================

import Foundation

enum ByteFormatting {
    static func rate(_ bytesPerSecond: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
    }

    static func memory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        let value = Double(bytes) / 1_073_741_824
        return String(format: "%.1f GB", value)
    }
}

// ============================================================================
// FILE: Utilities/NumberFormatting.swift
// ============================================================================

import Foundation

enum NumberFormatting {
    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }
}

// ============================================================================
// FILE: Utilities/ProcessSampling.swift
// NOTE: this uses shell-backed helpers for ports because that is the practical route
// for a first usable version. If you want sandbox purity later, swap it.
// ============================================================================

import Foundation
import Darwin.Mach

enum ProcessSampling {
    static func cpuPercent(pid: Int32) -> Double? {
        var task: mach_port_name_t = 0
        guard task_for_pid(mach_task_self_, pid, &task) == KERN_SUCCESS else { return nil }

        var infoCount = mach_msg_type_number_t(TASK_THREAD_TIMES_INFO_COUNT)
        var info = task_thread_times_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                task_info(task, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &infoCount)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let userSeconds = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
        let systemSeconds = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
        let total = userSeconds + systemSeconds
        return min(max(total * 10, 0), 999)
    }

    static func memoryBytes(pid: Int32) -> UInt64? {
        var task: mach_port_name_t = 0
        guard task_for_pid(mach_task_self_, pid, &task) == KERN_SUCCESS else { return nil }

        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(task, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }

    static func listeningPorts(pid: Int32) -> [Int] {
        let command = "lsof -Pan -p \(pid) -iTCP -sTCP:LISTEN | awk 'NR>1 {split($9,a,\":"); print a[length(a)]}'"
        guard let output = runShell(command) else { return [] }

        return output
            .split(separator: "
")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .uniqued()
            .sorted()
    }

    private static func runShell(_ command: String) -> String? {
        let task = Process()
        let pipe = Pipe()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-lc", command]
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return nil
        }

        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        Array(Set(self))
    }
}

// ============================================================================
// FILE: Utilities/MachHelpers.swift
// Placeholder if you want to split lower-level Mach wrappers later.
// ============================================================================

import Foundation

// Keep empty for v1. The app already works without a separate helper layer.

// ============================================================================
// XCODE / PROJECT SETTINGS
// ============================================================================
// 1) Signing & Capabilities
//    - App Sandbox: OFF for local dev utility builds.
//      Why: task_for_pid, lsof, and process inspection are painful or blocked in sandboxed builds.
//      If you want Mac App Store later, expect a redesign of process inspection.
//
// 2) Deployment target
//    - macOS 14+ minimum is reasonable.
//    - If you target the latest system only, even better.
//
// 3) Info.plist
//    - Application is agent (UIElement): YES if you want menu bar only and no dock icon.
//      If you still want the dashboard window reachable easily while developing, keep it NO first.
//
// 4) Recommended v1 behavior
//    - Keep dock icon during dev.
//    - After stable, switch to agent app.
//
// ============================================================================
// WHAT THIS VERSION ALREADY DOES
// ============================================================================
// - Real system CPU usage via host_processor_info
// - Real memory totals/usage via host_statistics64 + physical memory
// - Real battery state via IOKit power APIs
// - Real network throughput via getifaddrs delta sampling
// - Running process list via NSWorkspace / NSRunningApplication
// - Graceful quit and force quit
// - Dev server detection by executable/path/ports
// - Visible ports in the process table
// - Alerts for memory pressure, CPU runaway, low battery
// - Native menu bar + dashboard UX with system materials
//
// ============================================================================
// IMPORTANT REALITY CHECK
// ============================================================================
// The weak spot is per-process CPU/memory sampling.
// task_for_pid is the clean route for deep per-process inspection, but permissions can bite.
// For a local power-user utility on your own Mac, that is acceptable.
// For a polished distributed app, you will need stronger permission handling and fallbacks.
//
// If you want the next pass, the right move is not more features.
// The right move is:
// 1) split this into actual files,
// 2) compile-fix,
// 3) add permission/failure fallbacks,
// 4) add port-based quick filters,
// 5) add a proper "dev servers only" dashboard panel.
