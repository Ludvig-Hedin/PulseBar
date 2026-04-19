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
