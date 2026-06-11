import SwiftUI

/// Persistent banner shown at the top of the Storage tab when FDA is missing.
/// Explains why and links to System Settings.
struct FullDiskAccessBanner: View {
    let onOpenSettings: () -> Void
    let onRecheck: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text("Full Disk Access required")
                    .font(.headline)
                Text("Some categories (Mail Downloads, browser caches, system logs) can't be read until you grant PulseBar Full Disk Access in System Settings. If PulseBar isn't in the list, drag it in from Applications. Other scans still work without it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button {
                        onOpenSettings()
                    } label: {
                        Label("Open System Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button("I've granted access", action: onRecheck)
                        .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.orange.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
