import SwiftUI

/// Sheet that lets the user create or edit an Auto-Quit rule.
struct AutoQuitRuleEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var rule: AutoQuitRule
    private let runningAppNames: [String]
    private let onSave: (AutoQuitRule) -> Void

    init(rule: AutoQuitRule, runningAppNames: [String] = [], onSave: @escaping (AutoQuitRule) -> Void) {
        _rule = State(initialValue: rule)
        self.runningAppNames = runningAppNames
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-Quit Rule")
                    .font(.title3.weight(.bold))
                Text(rule.triggerMode == .processUsage
                     ? "Quit processes that match all conditions for the sustained duration below."
                     : "Quit a matching app once your system stays under RAM/CPU pressure for the sustained duration below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Form {
                Section("Identity") {
                    TextField("Rule name", text: $rule.name)
                    Toggle("Enabled", isOn: $rule.enabled)
                    Picker("Trigger", selection: $rule.triggerMode) {
                        Text("This process's own usage").tag(AutoQuitRule.TriggerMode.processUsage)
                        Text("System is low on RAM/CPU").tag(AutoQuitRule.TriggerMode.systemPressure)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Match") {
                    HStack {
                        TextField("Name contains (e.g. node, bun, python)", text: $rule.nameContains)
                        if !runningAppNames.isEmpty {
                            Menu {
                                ForEach(runningAppNames, id: \.self) { name in
                                    Button(name) { rule.nameContains = name }
                                }
                            } label: {
                                Image(systemName: "list.bullet")
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 28)
                            .help("Pick a running app")
                        }
                    }
                    TextField("Path contains (optional)", text: $rule.pathContains)
                }

                if rule.triggerMode == .processUsage {
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
                } else {
                    Section("System pressure thresholds") {
                        HStack {
                            Text("Free RAM below")
                            Spacer()
                            Stepper(value: $rule.sysFreeMemoryBelowPercent, in: 0...100, step: 5) {
                                Text(rule.sysFreeMemoryBelowPercent == 0 ? "off" : "\(Int(rule.sysFreeMemoryBelowPercent))%")
                                    .monospacedDigit()
                                    .frame(minWidth: 60, alignment: .trailing)
                            }
                        }
                        HStack {
                            Text("Free RAM below")
                            Spacer()
                            Stepper(value: $rule.sysFreeMemoryBelowGB, in: 0...32, step: 0.5) {
                                Text(rule.sysFreeMemoryBelowGB == 0 ? "off" : String(format: "%.1f GB", rule.sysFreeMemoryBelowGB))
                                    .monospacedDigit()
                                    .frame(minWidth: 70, alignment: .trailing)
                            }
                        }
                        HStack {
                            Text("CPU above")
                            Spacer()
                            Stepper(value: $rule.sysCPUAbovePercent, in: 0...100, step: 5) {
                                Text(rule.sysCPUAbovePercent == 0 ? "off" : "\(Int(rule.sysCPUAbovePercent))%")
                                    .monospacedDigit()
                                    .frame(minWidth: 60, alignment: .trailing)
                            }
                        }
                        Text("These are about your whole system, not this process. Any one crossing its threshold triggers the rule; leave a stepper at “off” to ignore it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                    Text(rule.triggerMode == .processUsage
                         ? "The process must keep matching the thresholds for this long before being quit. Stops one-off CPU spikes from triggering kills."
                         : "Your system must stay under pressure for this long before the matching app is quit. Stops a brief spike from triggering a kill.")
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
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 520, height: rule.triggerMode == .processUsage ? 580 : 640)
    }

    private var canSave: Bool {
        guard !rule.name.trimmingCharacters(in: .whitespaces).isEmpty,
              !rule.nameContains.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if rule.triggerMode == .systemPressure {
            guard rule.sysFreeMemoryBelowPercent > 0
                || rule.sysFreeMemoryBelowGB > 0
                || rule.sysCPUAbovePercent > 0 else { return false }
        }
        return true
    }
}
