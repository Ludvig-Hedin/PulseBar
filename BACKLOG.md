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

## WidgetKit extension (2026-07-12)

Added a macOS desktop-widget extension: `PulseBar/Shared/` (`WidgetSnapshot`
Codable model + `WidgetSnapshotStore` App Group bridge), `PulseBar/Services/
WidgetBridgeService.swift` (throttled `WidgetCenter.reloadAllTimelines()`), and
`PulseBar/PulseBarWidgets/` (six widget kinds — CPU, RAM, Network, Storage,
Dev Servers, Top Apps — each in small/medium/large). `PulseBarViewModel.refresh()`
publishes a snapshot every tick. `project.yml` gained a `PulseBarWidgets`
app-extension target (sandboxed, App Group `group.com.ludvighedin.PulseBar`,
explicit `WidgetKit.framework`/`SwiftUI.framework` SDK deps — XcodeGen does not
auto-link these for `app-extension` targets). `Package.swift` now includes
`Shared` so `swift build` stays green. Both `xcodebuild` schemes (`PulseBar`,
`PulseBarWidgets`) build clean; `#Preview` macros cover all 6 kinds × 3 sizes.

**Still needed before the widgets work on a real Mac** (cannot be done from
this environment): open the project in Xcode once, set a real
`DEVELOPMENT_TEAM` on both targets, and let Xcode register the
`group.com.ludvighedin.PulseBar` App Group with the developer account —
`DEVELOPMENT_TEAM` is currently `""`, and App Groups require a real team to
provision even for a free personal team.

**Deliberately out of scope for v1** (noted in the implementation plan, not
forgotten): `AppIntents`/configurable widgets (pick which dev server/app to
pin), Storage widget's "top junk category" breakdown (needs `categoryResults`
from the in-flux storage-revamp scan, not just `DiskUsage` totals), real
per-app icons in Top Apps (kind-based SF Symbol used instead — unreliable to
load `NSWorkspace` icons from a sandboxed extension).
