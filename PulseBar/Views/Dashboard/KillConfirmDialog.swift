import SwiftUI

struct KillConfirmDialog: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vm: PulseBarViewModel
    let row: ProcessRow

    var body: some View {
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
