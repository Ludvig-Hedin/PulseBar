# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**PulseBar** is a native macOS menubar utility that provides real-time system monitoring (CPU, memory, network, battery, processes). Built with SwiftUI, targeting macOS 14+. No external dependencies — pure Apple frameworks (Foundation, AppKit, Darwin.Mach, IOKit).

The repo contains two sub-projects:
- `PulseBar/` — the main application (primary focus)
- `test_proj/` — minimal placeholder Swift package (ignore)

---

## Build & Run

The project uses an Xcode project (`PulseBar/PulseBar.xcodeproj`). Open in Xcode to build and run:

```bash
open PulseBar/PulseBar.xcodeproj
```

Build from CLI via `xcodebuild`:
```bash
cd PulseBar
xcodebuild -project PulseBar.xcodeproj -scheme PulseBar -configuration Debug build
```

The project also has a `Package.swift`, so `swift build` works for compilation checks (but won't produce a proper .app bundle):
```bash
cd PulseBar
swift build
```

**Regenerate `.xcodeproj` from `project.yml`** (if you modify project structure):
```bash
cd PulseBar
xcodegen generate
```
> `xcodegen` must be installed: `brew install xcodegen`

---

## Architecture

**Pattern:** MVVM + Service Layer

```
PulseBarApp (@main)
  └─ AppState (ObservableObject root)
      └─ PulseBarViewModel (@MainActor, all app logic)
          ├─ 1s Timer → lightweight metrics (CPU, memory, network)
          ├─ Every 5 ticks → full refresh (processes, alerts) — heavier ops
          ├─ Services (stateless data fetchers)
          │   ├─ SystemMetricsService  — CPU % + memory via Darwin.Mach
          │   ├─ ProcessService        — NSWorkspace process enumeration
          │   ├─ NetworkService        — throughput via getifaddrs
          │   ├─ BatteryService        — IOKit battery state
          │   ├─ AlertsService         — threshold evaluation
          │   ├─ DevServerDetector     — heuristic (exe name + port hints)
          │   └─ KillService           — graceful/force terminate
          └─ Published @Properties → Views

Views
  ├─ MenuBar/  — compact popup (380px wide, top 5 processes + mini metrics)
  └─ Dashboard/ — full window (split nav: Overview, Processes, Dev Servers, Alerts)
```

**Key files:**
| File | Role |
|------|------|
| `App/PulseBarApp.swift` | Entry point, two scenes (MenuBarExtra + Window) |
| `App/AppState.swift` | ViewModel initialization, EnvironmentObject root |
| `ViewModels/PulseBarViewModel.swift` | All logic: refresh loop, filtering, sorting, kill confirmation |
| `Models/SystemSnapshot.swift` | System-wide metrics snapshot struct |
| `Models/ProcessRow.swift` | Per-process data + classification (`.app`, `.cli`, `.background`) |
| `Services/DevServerDetector.swift` | Dev server heuristics (name/path hints + port hints) |
| `Utilities/ProcessSampling.swift` | Per-process CPU/memory (task_for_pid) + port enumeration (lsof shell) |
| `Utilities/MachHelpers.swift` | Architectural notes on Mach API usage — read before touching metrics |

---

## Key Technical Constraints

**No App Sandbox** (intentional): `PulseBar.entitlements` explicitly disables sandboxing. This is required for `task_for_pid`, `lsof`, and process inspection. Do NOT enable sandboxing without a full redesign of `ProcessSampling.swift`.

**Concurrency model:**
- `PulseBarViewModel` is `@MainActor` — all published state updates happen on main thread
- Port enumeration (`lsof`) runs on `Task.detached` (slow shell command, ~100ms+)
- No async/await in Services — they use synchronous Darwin/IOKit APIs directly

**Alert thresholds** (in `AlertsService`):
- Memory: >90% = critical, 75–90% = warning
- CPU: ≥85% = warning
- Battery: ≤20% and not charging = warning

---

## Extending the App

- **New metric** → create a new `Service` in `Services/`, call it from `PulseBarViewModel.refresh()`
- **New UI section** → add a `View` in `Views/Dashboard/`, add a case to `DashboardTab` enum
- **New process action** → add method to `PulseBarViewModel`, wire into `ProcessRowView`
- **New alert rule** → modify `AlertsService.evaluate()`

---

## Storage / Cleaning subsystem

The Storage tab (sidebar group "STORAGE") is an actor-based scanner derived from
PureMac (MIT — see `THIRD_PARTY_LICENSES.md`). Key files:

- `Models/StorageCategory.swift` — source of truth for the 13 categories.
  Adding a category = new case + paths in `Locations.swift` + switch arm in
  `CategoryScanner.swift`.
- `Services/Cleaner/Locations.swift` — hardcoded path database; also the dev-root
  list and artifact-marker sets for Deep Scan.
- `Services/Cleaner/PathAllowlist.swift` — gates scans **and** admin escalation.
  Every deletion path must pass `isScanAllowed`; admin paths must additionally
  pass `isAdminEscalationAllowed`. Dev artifacts use a **separate** pair of gates
  (`isArtifactScanAllowed` for reads, `isArtifactDeleteAllowed` for marker-gated
  deletes) — `scanRoots` is NOT widened.
- `Services/Cleaner/ScanEngine.swift` — actor; scans on `Task.detached`; yields
  progress via `AsyncStream<Event>`. Categories run concurrently, bounded by
  `ScanBudget.maxConcurrentCategories`.
- `Services/Cleaner/CleanupService.swift` — actor; trash / permanent / admin
  modes. AppleScript escalation lives here (not in `CommandRunner`). `.devArtifacts`
  items are force-trashed (never permanent/admin) via the marker gate.
- `Services/Cleaner/FullDiskAccessDetector.swift` — probes TCC paths; memoised 30s.
- `Services/StorageService.swift` — `@MainActor` orchestrator + `@Published`
  state. Disk-usage probe runs every `PulseBarViewModel.refresh()` tick.

Scan tiers, auto-clean, inventory, history:
- `Models/ScanTier.swift` / `Models/ScanBudget.swift` — Quick / Deep / Ultra tiers
  and their per-run resource envelopes (deadlines, caps, concurrency).
- `Services/Cleaner/AutoCleanCoordinator.swift` — the **only** unattended
  scan→delete path. Mode is a hard-pinned local `.trash` constant (never from the
  persisted `AutoCleanPolicy`); a byte/item circuit breaker aborts + notifies
  instead of deleting when a run finds more than expected. First use gated by a
  one-time consent sheet.
- `Services/Cleaner/ArtifactEnumerator.swift` — Deep Scan; prune-on-hit walk that
  reports whole marker dirs (`node_modules`, `build`, `target`, `.venv`, …).
  Ambiguous markers require a sibling project manifest.
- `Services/Cleaner/DiskInventoryEngine.swift` — Ultra Scan; read-only whole-disk
  size map producing `InventoryNode` (no path into `CleanupService`). Bypasses the
  allowlist for READS only; deletion stays gated.
- `Services/ScanHistoryStore.swift` — persists each multi-category scan as JSON
  under `~/Library/Application Support/PulseBar/scans/` (lean `index.json` + fat
  `<uuid>.json`). Provides repeat-offender rollup + trend series. `AutoCleanPolicy`
  persists via `PreferencesService`.
- UI: `Views/Dashboard/Storage/DiskInventoryView.swift` (Disk Map subview) and
  `Views/Dashboard/Storage/History/*` (the `.storageHistory` sidebar tab, using
  Swift Charts). New source files under existing dirs are picked up by
  `xcodegen generate`; Swift Charts autolinks on `import Charts`.

Safety guardrails:
- Trash-first by default; permanent + admin opt-in per cleanup.
- Symlink resolution + path re-stat (TOCTOU) immediately before delete.
- 10k file cap and 30s deadline per category scan.
- `CommandRunner` never spawns a shell; `[String]` args only.
- AppleScript shell-quoting validated against a banned-character list; max 50
  paths per batch; fixed reason string.
- Storage category actionability is explicit: normal cache/log/dev-artifact
  categories are selectable, Large Files is reveal-only, Purgeable is
  informational, and Docker is an external `docker system prune -f` action.
  Do not route Docker/Purgeable/Large Files through the normal file deletion
  flow.
- Docker prune intentionally omits `--volumes`; volume deletion requires a
  separate product decision and stronger confirmation copy.
- Auto-clean (Quick Clean) is **trash-only forever** and manual-only (no
  on-launch/scheduled trigger). Never read the deletion mode from the persisted
  policy — the coordinator pins `.trash` locally.
- Ultra Scan is read-only: `InventoryNode` has no route to `CleanupService`.
  Cleaning from the Disk Map (reconstructing a `CleanableItem` that must re-pass
  the gates) is intentionally deferred — see `BACKLOG.md`.

**Sandbox:** `PulseBar.entitlements` sets `com.apple.security.app-sandbox=false`.
Required for both the existing process inspection (`task_for_pid`, `lsof`) and
the new full-filesystem scans. Do not re-enable.

---

## Naming Conventions (Swift)

- PascalCase: types, structs, enums, views
- camelCase: properties, functions
- Suffix `Service` for data providers, `ViewModel` for state containers, `Section` for dashboard view components
- No abbreviations: `cpuUsagePercent` not `cpuPct`
