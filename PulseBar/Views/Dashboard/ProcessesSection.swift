import SwiftUI

struct ProcessesSection: View {
    @EnvironmentObject private var vm: PulseBarViewModel
    @EnvironmentObject private var appState: AppState

    @State private var showColumnPicker = false
    @State private var showKillConfirm = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ── Filter tabs + view-mode toggle ──────────────────────────────
            HStack {
                filterTabsView
                Spacer()
                viewModeToggle
            }

            // ── Search row ───────────────────────────────────────────────────
            HStack(spacing: 10) {
                SearchBar(text: $vm.searchText, placeholder: "Search processes")
                    .focused($searchFocused)

                Text(countLabel)
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
                .help("Show or hide columns")
                .popover(isPresented: $showColumnPicker, arrowEdge: .bottom) {
                    columnPickerPopover
                }

                // Select mode controls
                if vm.isSelectMode {
                    Button {
                        vm.selectAll()
                    } label: {
                        Label("All", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Select every visible process (⌘A)")
                    .keyboardShortcut("a", modifiers: .command)

                    Button {
                        showKillConfirm = true
                    } label: {
                        Label(
                            vm.selectedProcessPIDs.isEmpty
                                ? "Quit Selected"
                                : "Quit \(vm.selectedProcessPIDs.count)",
                            systemImage: "xmark.circle.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(.red)
                    .disabled(vm.selectedProcessPIDs.isEmpty)
                    .help("Force quit all selected processes")

                    Button("Done") {
                        vm.toggleSelectMode()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button {
                        vm.toggleSelectMode()
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Select multiple processes to quit at once. Use shift-click for a range.")
                }
            }
            .animation(.easeInOut(duration: 0.18), value: vm.isSelectMode)

            // ── Body: table or cards ────────────────────────────────────────
            switch vm.processViewMode {
            case .table:
                tableBody
            case .cards:
                ProcessCardsView()
                    .environmentObject(appState)
                    .environmentObject(vm)
            }
        }
        // Cmd+F focuses the search field — hidden button attached as background.
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        // Multi-kill confirmation
        .confirmationDialog(
            "Force quit \(vm.selectedProcessPIDs.count) selected process\(vm.selectedProcessPIDs.count == 1 ? "" : "es")?",
            isPresented: $showKillConfirm,
            titleVisibility: .visible
        ) {
            Button("Force Quit", role: .destructive) {
                vm.forceKillSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will forcefully terminate the selected processes. Unsaved work may be lost.")
        }
    }

    /// Compact "12 of 312" label so the user knows what's filtered out.
    private var countLabel: String {
        let shown = vm.filteredProcesses.count
        let total = vm.processes.count
        if shown == total { return "\(shown) shown" }
        return "\(shown) of \(total)"
    }

    /// Empty state with a one-click reset back to "All / no search".
    private var emptyState: some View {
        VStack(spacing: 10) {
            EmptyStateView(
                title: "No processes match",
                subtitle: "Try a different filter or clear your search."
            )
            if vm.filter != .all || !vm.searchText.isEmpty {
                Button("Clear filters") {
                    vm.filter = .all
                    vm.searchText = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Table body (extracted so the view-mode switch stays readable)

    private var tableBody: some View {
        VStack(spacing: 0) {
            // Column headers — spacing matches ProcessRowView's HStack(spacing:14)
            HStack(spacing: 14) {
                if vm.isSelectMode {
                    Color.clear.frame(width: 24)
                }

                SortableHeader(label: "Name", column: .name, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if vm.visibleColumns.contains(.cpu) {
                    SortableHeader(label: "CPU", column: .cpu, alignment: .trailing)
                        .frame(width: 80, alignment: .trailing)
                }
                if vm.visibleColumns.contains(.memory) {
                    SortableHeader(label: "Memory", column: .memory, alignment: .trailing)
                        .frame(width: 110, alignment: .trailing)
                }
                if vm.visibleColumns.contains(.uptime) {
                    SortableHeader(label: "Uptime", column: .uptime, alignment: .trailing)
                        .frame(width: 70, alignment: .trailing)
                }
                if vm.visibleColumns.contains(.ports) {
                    SortableHeader(label: "Ports", column: .ports, alignment: .leading)
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
                emptyState
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

    // MARK: - View-mode toggle (table vs cards)

    private var viewModeToggle: some View {
        Picker("", selection: $vm.processViewMode) {
            ForEach(PreferencesService.ProcessViewMode.allCases) { mode in
                Image(systemName: mode.systemImage)
                    .tag(mode)
                    .help(mode.label)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 80)
        .help("Switch between table and cards view")
    }

    // MARK: - Filter tabs

    private var filterTabsView: some View {
        HStack(spacing: 2) {
            ForEach(PulseBarViewModel.Filter.allCases) { filter in
                Button(filter.rawValue) {
                    vm.filter = filter
                }
                .buttonStyle(FilterTabButtonStyle(isSelected: vm.filter == filter))
                .help(helpText(for: filter))
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
        )
    }

    private func helpText(for filter: PulseBarViewModel.Filter) -> String {
        switch filter {
        case .all: return "Show every process"
        case .devServers: return "Show processes that look like dev servers (Node, Vite, Postgres, Redis, ports like 3000, etc.)"
        case .heavy:
            let cpu = PreferencesService.shared.heavyCpuPercent
            let mem = PreferencesService.shared.heavyMemoryGB
            return "Show processes using ≥ \(cpu)% CPU or ≥ \(mem) GB RAM"
        case .apps: return "Show user-facing applications only"
        case .cli: return "Show command-line tools only"
        }
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

// MARK: - Sortable column header
private struct SortableHeader: View {
    @EnvironmentObject private var vm: PulseBarViewModel
    let label: String
    let column: PulseBarViewModel.SortColumn
    let alignment: HorizontalAlignment

    var body: some View {
        Button {
            vm.tapSort(column)
        } label: {
            HStack(spacing: 4) {
                if alignment == .trailing { Spacer(minLength: 0) }
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isActive ? .primary : .secondary)
                if isActive {
                    Image(systemName: vm.sortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                if alignment == .leading { Spacer(minLength: 0) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sort by \(label)")
    }

    private var isActive: Bool { vm.sortColumn == column }
}
