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
