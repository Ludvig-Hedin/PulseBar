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
