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

## Naming Conventions (Swift)

- PascalCase: types, structs, enums, views
- camelCase: properties, functions
- Suffix `Service` for data providers, `ViewModel` for state containers, `Section` for dashboard view components
- No abbreviations: `cpuUsagePercent` not `cpuPct`
