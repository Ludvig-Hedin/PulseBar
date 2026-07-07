# Code Review Backlog

## Bug Hunt — 2026-05-23

### Auto-fixed (8 issues)

- `PulseBar/ViewModels/PulseBarViewModel.swift` (uptime sort) — sort was inverted.
  Sorting by `launchDate ascending` ordered oldest-first (longest uptime), then
  `descending` reversed it to newest-first (shortest uptime). Tapping "Uptime" with
  the natural descending default put short-running processes at the top. Replaced
  with a derived `uptime` comparator so ascending = shortest first, descending =
  longest first; rows with no launch date sink to the bottom.
- `PulseBar/Services/NetworkService.swift` — `max(delta, 1)` floored the sample
  interval at one second, which halved reported throughput at the default 2 s refresh
  interval and quartered it at 0.5 s. Lowered to 0.05 s (matches the per-process CPU
  sampler's elapsed guard).
- `PulseBar/Utilities/ProcessSampling.swift` — `cpuSamples` dict grew unbounded over
  long-running sessions: a sample was inserted on every `cpuPercent(pid:)` call, but
  nothing removed entries when processes exited. Added
  `ProcessSampling.prune(activePIDs:)` and wired it into the same place as
  `AppIconService.prune(activePIDs:)`.
- `PulseBar/ViewModels/PulseBarViewModel.swift` (refresh) — call
  `ProcessSampling.prune` on full refresh so the new prune helper actually runs.
- `PulseBar/Services/NotificationService.swift` — RAM-threshold loop fired one banner
  per crossed tier. At 95 % RAM with the default [50, 70, 80, 90] thresholds the user
  got four banners in rapid succession. Now only the highest-crossed tier fires per
  evaluation; lower tiers still re-arm independently when RAM drops below them.
- `PulseBar/Utilities/ProcessSampling.swift` (`runShell`) — `task.waitUntilExit()`
  blocked indefinitely if `lsof` hung (stuck NFS mount, hostile fs). Added a 5 s
  `DispatchWorkItem` watchdog that calls `task.terminate()` and cancels itself on
  clean exit; non-zero exit is treated as no result.
- `PulseBar/ViewModels/PulseBarViewModel.swift` (`refresh`) — `Task { … }` was
  fire-and-forget; the timer, the post-kill `asyncAfter`, and the ⌘R button could
  spawn concurrent refresh Tasks whose completion order was non-deterministic, so a
  stale snapshot could land after a fresher one. Gated with an `isRefreshing` flag
  (`guard !isRefreshing` on entry, `defer { isRefreshing = false }` on exit).
- `PulseBar/Views/Dashboard/DashboardTab.swift` — promoted the canonical
  `DashboardTab` enum into the clean-named file (it previously lived in
  `DashboardTab 2.swift`). `DashboardTab 2.swift` is now the empty stub. Build still
  references both files in `project.pbxproj`; left as stub per user instruction. Run
  `xcodegen generate` after deleting the stub file on disk to fully clean up the
  project structure.

### Known limitations (1)

- `PulseBar/Services/NetworkService.swift` — `if_data.ifi_ibytes` and `ifi_obytes`
  are `u_int32_t`. On a hot interface those wrap every ~4 GB; the wrap is treated as
  "counter reset" and the rate goes to zero for one tick. Acceptable for v1, but a
  proper fix uses 64-bit counters via `sysctlbyname("net.link.generic.system…")` or
  per-interface accumulators.

---

## Bug Hunt — 2026-05-23 (Storage feature)

### Auto-fixed (high-confidence) — 14 issues

- `PulseBar/Services/Cleaner/PathAllowlist.swift` (`isSafeForShellEscalation`) —
  banned char list was too narrow. Added `$`, `;`, `|`, `&`, `<`, `>`, `(`, `)`,
  `*`, `?`, `[`, `]`, `{`, `}`, `!`, `#`, `~`, `\t`, `"` so paths that survive
  validation can be neither parameter-expanded by `/bin/sh` nor mis-quoted by
  AppleScript. Belt-and-suspenders with the existing single-quote wrapping.
- `PulseBar/Services/Cleaner/DockerProbe.swift` (`parseHumanSize`) — `KIB`/`MIB`/
  `GIB`/`TIB`/`PIB` (newer Docker output) fell through to multiplier 1, so a
  reclaimable `1.23 GiB` was reported as 1 byte. Added all binary-suffix cases
  with 1024-based multipliers and changed `default` from `1` to `0` so unknown
  suffixes report 0 rather than the raw value.
- `PulseBar/Services/Cleaner/FullDiskAccessDetector.swift` (`probe`) — successful
  branch leaked the open `FileHandle` (probe runs every 30 s). Now closes the
  descriptor before returning.
- `PulseBar/Services/Cleaner/FileEnumerator.swift` — added `minSizeBytes`
  parameter so the size filter runs *inside* the enumerator instead of after the
  file cap is reached.
- `PulseBar/Services/Cleaner/CategoryScanner.swift` (`scanLargeFiles`) — pushed
  the 100 MiB filter into `FileEnumerator` via the new parameter so a tree with
  >5000 small files no longer returns zero large files.
- `PulseBar/Services/Cleaner/ScanEngine.swift` — removed dead `cancellationRequested`
  state (worker only reads `Task.isCancelled`) and added a `generation` counter so a
  superseded scan's late completion no longer overwrites the newer scan's results.
- `PulseBar/ViewModels/StorageViewModel.swift` (`selectAll`/`deselectAll`) — used
  `result.items` regardless of search filter, so "Select All" in a filtered list
  selected hidden items too. Switched to `filteredItems(for:)`. Also no-ops on
  reveal-only categories.
- `PulseBar/Models/StorageState.swift` (`totalJunkBytes`) — Docker reclaimable
  bytes are not deletable from PulseBar (only `docker system prune` reclaims them),
  so excluding `.docker` from the "Junk found" total prevents overstatement.
- `PulseBar/Views/Dashboard/Storage/CleanableItemRow.swift` — dropped dead folder
  icon branch (`FileEnumerator` always emits files with `isDirectory: false`).
- `PulseBar/Services/Cleaner/Locations.swift` (`mailDownloads`) — legacy
  `~/Library/Mail Downloads` was retired in macOS Sierra. Removed the dead entry.
- `PulseBar/Views/Dashboard/Storage/CategoryDetailView.swift` — dropped redundant
  `selectedCategory = nil` after `dismiss()`; `.sheet(item:)` clears the binding
  itself.
- `PulseBar/Views/Dashboard/Storage/StorageSettingsView.swift` — dropped
  redundant `Task { await MainActor.run { … } }` around an action that already
  runs on `@MainActor`.
- `PulseBar/Services/Cleaner/CleanupService.swift` — moved the nested
  `EscalationError` struct out of the function body to its proper type-level
  position; behaviour unchanged, scope clearer.

### UX polish — 9 fixes

- `StickyCleanBar.swift` — removed `.tint(.red)` from the Clean button. Red
  contradicted the default Trash-mode (recoverable) semantics. Added a `help()`
  tooltip naming the keyboard shortcut.
- `StorageViewModel.swift` — defaulted `subview` to `.categories` so users land on
  the actionable surface (Smart Scan + category list) instead of the empty
  Dashboard hero.
- `CategoryDetailView.swift` — sort menu label now shows the active direction
  (`Sort: Size ↓` / `↑`).
- `CategoryDetailView.swift` — reveal-only banner moved *above* the toolbar so
  users see the context before encountering an apparently-missing Select All.
- `CategoryDetailView.swift` — Select All / Deselect All buttons are hidden in
  reveal-only categories where selection is a no-op.
- `CategoryRow.swift` — added a `lock.shield.fill` badge to FDA-required
  categories when access hasn't been granted, plus a `help()` on the chevron.
- `StorageSection.swift` — cleanup summary toast now has a "Show in Trash" button
  for Trash-mode cleanups, and auto-dismisses after 8 s.
- `StorageOverviewCallout.swift` — renamed "Scan now" → "Scan & open Storage"
  (and forces the destination subview to `.categories`) so the button's
  side-effect-then-navigate behaviour is no longer surprising.

### Needs human review (deferred) — 5 issues

- **C2: AppleScript prompt escaping (latent).** `CleanupService.escalationReason`
  is currently a fixed constant and safe. If it ever becomes user- or
  localization-driven, the AppleScript double-quoted interpolation needs the
  same escape pass as the shell command. Add the escape proactively when the
  constant is made dynamic.
- **C3: TOCTOU via symlink swap between re-stat and unlink.**
  `CleanupService.delete` re-checks the resolved path, then `removeItem` happens
  in a separate syscall. A determined attacker can swap a symlink in the
  microseconds between the two. Robust fix: open with `O_NOFOLLOW`, fstat the
  fd, unlink via fd. Out of scope for v1 — risk is bounded by the
  `PathAllowlist` denying user-data directories outright.
- **M4: `CommandRunner.run` busy-waits with `Thread.sleep`.** Today it's only
  called from `Task.detached` workers so the blocking is harmless. If any
  `@MainActor` caller is added (e.g. a "Test Docker connectivity" button) the
  UI will freeze. Convert to an async wrapper using `Process.terminationHandler`
  + a continuation when needed.
- **M6: `StorageService.emptyTrash` is unwired.** Implemented but no UI button
  invokes it. Either ship an "Empty Trash" action on the Trash category detail
  view, or remove the dead code.
- **Structural: Storage tab has two nav layers.** Sidebar tab + segmented
  Dashboard / Categories / Settings inside it. Consider collapsing Dashboard
  hero into the Categories view as a header, and routing Storage Settings into
  the macOS Settings scene (⌘,) where the rest of the app's prefs already live.

---

## Bug Hunt — 2026-07-07 (Storage cleaner UX + scan coverage)

### Auto-fixed (high-confidence) — 5 issues

- `PulseBar/PulseBar.xcodeproj/project.pbxproj` — `AllFilesView.swift` existed
  on disk and compiled under SwiftPM, but was missing from the Xcode target,
  causing `xcodebuild` to fail at `StorageSection.swift`.
- `PulseBar/Services/Cleaner/CategoryScanner.swift` (`scanNodeCache`) — static
  cache roots declared in `Locations.staticPaths(for: .nodeCache)` were never
  scanned, so Gradle, Maven, Cargo, and static dev-cache paths were missed.
- `PulseBar/Models/StorageState.swift` (`totalJunkBytes`) — Large Files is
  reveal-only user data, but an individual Large Files scan still inflated the
  normal "junk" total. Excluded it from cleanable totals.
- `PulseBar/Services/Cleaner/CategoryScanner.swift` (`scanDocker`) — Docker
  reclaimable bytes were represented as a synthetic `/dev/null` item. Removed
  the fake file and kept Docker as an external prune action with a byte total.
- Storage category UX — Docker, Purgeable, and Large Files used file-list
  patterns that implied normal deletion even when they are external,
  informational, or reveal-only categories. Added explicit action states and
  routed category taps into the Files review surface instead of a modal.

### Validation target

- `swift build`
- `xcodebuild -project PulseBar.xcodeproj -scheme PulseBar -configuration Debug build`
