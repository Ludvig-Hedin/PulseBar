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
