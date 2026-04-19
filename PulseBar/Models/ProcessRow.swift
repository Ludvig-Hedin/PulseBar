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

    /// Human-readable uptime (e.g. "1h 23m") or nil if launch date unknown.
    var uptimeString: String? {
        guard let launch = launchDate else { return nil }
        let seconds = Int(Date().timeIntervalSince(launch))
        guard seconds >= 0 else { return nil }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }

    enum Kind: String, CaseIterable, Hashable {
        case app = "App"
        case cli = "CLI"
        case background = "Background"
        case unknown = "Unknown"
    }
}
