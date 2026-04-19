import SwiftUI

/// Renders an app icon for a process, falling back to a SF Symbol when the OS
/// can't provide one (CLI tools, terminated processes, etc.).
struct ProcessIconView: View {
    let row: ProcessRow
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let nsImage = AppIconService.shared.icon(for: row) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: row.isLikelyDevServer ? "server.rack" : "app.dashed")
                    .foregroundStyle(row.isLikelyDevServer ? .orange : .secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
