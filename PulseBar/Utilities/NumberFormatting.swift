import Foundation

enum NumberFormatting {
    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }
}
