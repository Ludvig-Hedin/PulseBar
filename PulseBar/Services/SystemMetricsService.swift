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
            let index = Int32(CPU_STATE_MAX) * Int32(cpu)

            let user = Double(cpuInfo[Int(index + Int32(CPU_STATE_USER))] - previousCPUInfo[Int(index + Int32(CPU_STATE_USER))])
            let system = Double(cpuInfo[Int(index + Int32(CPU_STATE_SYSTEM))] - previousCPUInfo[Int(index + Int32(CPU_STATE_SYSTEM))])
            let nice = Double(cpuInfo[Int(index + Int32(CPU_STATE_NICE))] - previousCPUInfo[Int(index + Int32(CPU_STATE_NICE))])
            let idle = Double(cpuInfo[Int(index + Int32(CPU_STATE_IDLE))] - previousCPUInfo[Int(index + Int32(CPU_STATE_IDLE))])

            let activeValue = user + system + nice
            let totalValue = activeValue + idle
            if totalValue > 0 {
                totalUsage += activeValue / totalValue
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
