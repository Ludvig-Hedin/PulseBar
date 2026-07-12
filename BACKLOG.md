# Backlog

Deferred work, logged as it comes up. Auto-do items when relevant to the current task.

## Storage revamp follow-ups (2026-07-12)

- **Ultra Scan → gated clean.** Disk Map is currently reveal-only. Add a "Clean
  this" action that reconstructs a `CleanableItem` from an `InventoryNode` and
  routes through the normal confirmation flow (must re-pass `isScanAllowed` /
  `isArtifactDeleteAllowed`). Keep deletion fully gated — never bulk-delete from
  the map. Files: `DiskInventoryView.swift`, `StorageViewModel.swift`.
- **Configurable dev-artifact roots.** Deep Scan currently walks the whole home
  folder (`Locations.devArtifactRoots = [home]`). Surface a Settings control to
  add/remove roots and persist via `PreferencesService`.
- **Auto-clean settings UI.** `AutoCleanPolicy` (categories, age filter, byte/item
  circuit-breaker ceilings) is persisted but only the master opt-in is exposed via
  the consent sheet. Add a Settings panel to tune categories/limits.
- **Deep Scan false-positive tuning.** `node_modules` inside app-support dirs
  (e.g. `~/.vscode/extensions`, `~/.cursor`) are reported as artifacts. Trash-only
  makes this recoverable, but consider excluding known editor-extension trees.
- **project.yml Charts/Shared note.** New Storage files auto-glob via `xcodegen
  generate`. Swift Charts autolinks on `import Charts`; no explicit dependency was
  added. If a future toolchain stops autolinking, add it to the `PulseBar` target.

## Cross-session note

- A parallel session added a **WidgetKit extension** (`PulseBar/Shared/`,
  `PulseBar/Services/WidgetBridgeService.swift`, `PulseBar/PulseBarWidgets/`, plus
  edits to `PulseBarViewModel.swift`). That work is **not** part of the
  `storage-revamp` branch and its `Shared/` sources are not yet in `Package.swift`,
  which breaks `swift build` in the shared working tree. Left untouched — owner to
  integrate (add `Shared` to Package.swift sources, wire the widget target).
