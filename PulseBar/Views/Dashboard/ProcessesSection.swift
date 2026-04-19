import SwiftUI

struct ProcessesSection: View {
    @EnvironmentObject private var vm: PulseBarViewModel
    @EnvironmentObject private var appState: AppState

    @State private var showColumnPicker = false
    @State private var showKillConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ── Title + rounded filter tabs ──────────────────────────────────
            HStack {
                Text("Processes")
                    .font(.title3.weight(.semibold))
                Spacer()
                filterTabsView
            }

            // ── Search row ───────────────────────────────────────────────────
            HStack(spacing: 10) {
                SearchBar(text: $vm.searchText, placeholder: "Search name, bundle, path, port")

                Text("\(vm.filteredProcesses.count) shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()

                // Column visibility picker
                Button {
                    showColumnPicker.toggle()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 15))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Show/hide columns")
                .popover(isPresented: $showColumnPicker, arrowEdge: .bottom) {
                    columnPickerPopover
                }

                // Select mode controls
                if vm.isSelectMode {
                    Button {
                        showKillConfirm = true
                    } label: {
                        Label(
                            vm.selectedProcessPIDs.isEmpty
                                ? "Kill Selected"
                                : "Kill \(vm.selectedProcessPIDs.count)",
                            systemImage: "xmark.circle.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(.red)
                    .disabled(vm.selectedProcessPIDs.isEmpty)

                    Button("Cancel") {
                        vm.toggleSelectMode()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                } else {
                    Button {
                        vm.toggleSelectMode()
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: vm.isSelectMode)

            // ── Table ────────────────────────────────────────────────────────
            VStack(spacing: 0) {
                // Column headers — spacing matches ProcessRowView's HStack(spacing:14)
                HStack(spacing: 14) {
                    // Placeholder aligns with per-row select checkbox
                    if vm.isSelectMode {
                        Color.clear.frame(width: 24)
                    }

                    SortableHeader(label: "Name", column: .name)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if vm.visibleColumns.contains(.cpu) {
                        SortableHeader(label: "CPU", column: .cpu)
                            .frame(width: 80, alignment: .leading)
                    }
                    if vm.visibleColumns.contains(.memory) {
                        SortableHeader(label: "Memory", column: .memory)
                            .frame(width: 110, alignment: .leading)
                    }
                    if vm.visibleColumns.contains(.uptime) {
                        SortableHeader(label: "Uptime", column: .uptime)
                            .frame(width: 70, alignment: .leading)
                    }
                    if vm.visibleColumns.contains(.ports) {
                        SortableHeader(label: "Ports", column: .ports)
                            .frame(width: 120, alignment: .leading)
                    }

                    Text("Actions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .animation(.easeInOut(duration: 0.18), value: vm.isSelectMode)

                Divider()

                if vm.filteredProcesses.isEmpty {
                    EmptyStateView(
                        title: "No matching processes",
                        subtitle: "Change the filter or search less aggressively."
                    )
                    .padding(20)
                } else {
                    ForEach(vm.filteredProcesses) { row in
                        ProcessRowView(row: row)
                            .environmentObject(appState)
                            .environmentObject(vm)
                        Divider()
                    }
                }
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        // Multi-kill confirmation
        .confirmationDialog(
            "Force quit \(vm.selectedProcessPIDs.count) selected process\(vm.selectedProcessPIDs.count == 1 ? "" : "es")?",
            isPresented: $showKillConfirm,
            titleVisibility: .visible
        ) {
            Button("Force Quit All", role: .destructive) {
                vm.forceKillSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will forcefully terminate the selected processes. This action cannot be undone.")
        }
    }

    // MARK: - Rounded filter tabs
    private var filterTabsView: some View {
        HStack(spacing: 2) {
            ForEach(PulseBarViewModel.Filter.allCases) { filter in
                Button(filter.rawValue) {
                    vm.filter = filter
                }
                .buttonStyle(FilterTabButtonStyle(isSelected: vm.filter == filter))
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
        )
    }

    // MARK: - Column picker popover
    private var columnPickerPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visible Columns")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(PulseBarViewModel.VisibleColumn.allCases) { column in
                Toggle(column.rawValue, isOn: Binding(
                    get: { vm.visibleColumns.contains(column) },
                    set: { newValue in
                        if newValue != vm.visibleColumns.contains(column) {
                            vm.toggleColumnVisibility(column)
                        }
                    }
                ))
                .toggleStyle(.checkbox)
            }
        }
        .padding(14)
        .frame(minWidth: 160)
    }
}

// MARK: - Filter tab button style (rounder + slightly bigger, same text size)
private struct FilterTabButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
            )
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Sortable column header (always left-aligned)
private struct SortableHeader: View {
    @EnvironmentObject private var vm: PulseBarViewModel
    let label: String
    let column: PulseBarViewModel.SortColumn

    var body: some View {
        Button {
            vm.tapSort(column)
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isActive ? .primary : .secondary)
                if isActive {
                    Image(systemName: vm.sortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sort by \(label)")
    }

    private var isActive: Bool { vm.sortColumn == column }
}
