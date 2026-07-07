import SwiftUI

/// Sheet that lets the user create or edit an Auto-Quit rule.
struct AutoQuitRuleEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var rule: AutoQuitRule
    private let onSave: (AutoQuitRule) -> Void

    init(rule: AutoQuitRule, onSave: @escaping (AutoQuitRule) -> Void) {
        _rule = State(initialValue: rule)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-Quit Rule")
                    .font(.title3.weight(.bold))
                Text("Quit processes that match all conditions for the sustained duration below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Form {
                Section("Identity") {
                    TextField("Rule name", text: $rule.name)
                    Toggle("Enabled", isOn: $rule.enabled)
                }

                Section("Match") {
                    TextField("Name contains (e.g. node, bun, python)", text: $rule.nameContains)
                    TextField("Path contains (optional)", text: $rule.pathContains)
                }

                Section("Thresholds") {
                    HStack {
                        Text("Min CPU%")
                        Spacer()
                        Stepper(value: $rule.minCpuPercent, in: 0...100, step: 5) {
                            Text(rule.minCpuPercent == 0 ? "off" : "\(Int(rule.minCpuPercent))%")
                                .monospacedDigit()
                                .frame(minWidth: 60, alignment: .trailing)
                        }
                    }
                    HStack {
                        Text("Min Memory")
                        Spacer()
                        Stepper(value: $rule.minMemoryMB, in: 0...32_000, step: 100) {
                            Text(rule.minMemoryMB == 0 ? "off" : "\(Int(rule.minMemoryMB)) MB")
                                .monospacedDigit()
                                .frame(minWidth: 90, alignment: .trailing)
                        }
                    }
                    Text("If both CPU and memory are set, either signal triggers the rule. If neither is set, the rule fires on name + uptime alone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Timing") {
                    HStack {
                        Text("Min uptime")
                        Spacer()
                        Stepper(value: $rule.minUptimeSeconds, in: 0...86_400, step: 30) {
                            Text("\(rule.minUptimeSeconds) s")
                                .monospacedDigit()
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                    }
                    HStack {
                        Text("Sustained for")
                        Spacer()
                        Stepper(value: $rule.sustainedSeconds, in: 5...3600, step: 15) {
                            Text("\(rule.sustainedSeconds) s")
                                .monospacedDigit()
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                    }
                    Text("The process must keep matching the thresholds for this long before being quit. Stops one-off CPU spikes from triggering kills.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Action") {
                    Toggle("Force quit instead of graceful", isOn: $rule.force)
                    if rule.force {
                        Label("Force quit terminates immediately — unsaved work is lost.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save") {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(rule.name.trimmingCharacters(in: .whitespaces).isEmpty
                          || rule.nameContains.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520, height: 580)
    }
}
