# PulseBar

A native macOS menu bar application for real-time system monitoring. Live CPU, memory, network, battery, and process metrics — always one click away.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![License](https://img.shields.io/badge/license-GPL--3.0-green)

---

## Features

- **CPU usage** — real-time percentage via Darwin Mach APIs
- **Memory pressure** — used/total RAM with warning thresholds
- **Network throughput** — live upload/download rates
- **Battery status** — charge level, charging state, and low-battery alerts
- **Process monitor** — top processes by CPU/memory, with app helper processes aggregated
- **Dev server detector** — heuristic detection of running dev servers (Vite, Next.js, etc.)
- **Kill processes** — graceful or force-terminate any process directly from the UI
- **Smart alerts** — threshold-based notifications (memory >90%, CPU ≥85%, battery ≤20%)

---

## Screenshots

> Coming soon.

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+
- No App Sandbox (required for low-level system access via `task_for_pid`)

---

## Getting Started

### Open in Xcode

```bash
git clone https://github.com/Ludvig-Hedin/PulseBar.git
cd PulseBar
open PulseBar/PulseBar.xcodeproj
```

Then press **⌘R** to build and run.

### Build from the command line

```bash
cd PulseBar
xcodebuild -project PulseBar.xcodeproj -scheme PulseBar -configuration Debug build
```

### Compilation check (no .app bundle)

```bash
cd PulseBar
swift build
```

### Regenerate `.xcodeproj` from `project.yml`

If you modify the project structure, regenerate the Xcode project:

```bash
brew install xcodegen   # first time only
cd PulseBar
xcodegen generate
```

---

## Architecture

**Pattern:** MVVM + Service Layer — no external dependencies, pure Apple frameworks.

```
PulseBarApp (@main)
  └─ AppState (ObservableObject root)
      └─ PulseBarViewModel (@MainActor, all app logic)
          ├─ 1s Timer  → lightweight metrics (CPU, memory, network)
          ├─ Every 5s  → full refresh (processes, alerts)
          ├─ Services (stateless data fetchers)
          │   ├─ SystemMetricsService  — CPU % + memory (Darwin.Mach)
          │   ├─ ProcessService        — process enumeration (NSWorkspace + kernel PID tree)
          │   ├─ NetworkService        — throughput (getifaddrs)
          │   ├─ BatteryService        — battery state (IOKit)
          │   ├─ AlertsService         — threshold evaluation
          │   ├─ DevServerDetector     — heuristic detection
          │   └─ KillService           — graceful / force terminate
          └─ @Published properties → Views

Views
  ├─ MenuBar/    — compact popup, top 5 processes + mini metrics
  └─ Dashboard/  — full window with Overview, Processes, Dev Servers, Alerts
```

### Key files

| File | Role |
|------|------|
| `App/PulseBarApp.swift` | Entry point — two scenes (MenuBarExtra + Window) |
| `App/AppState.swift` | ViewModel init, EnvironmentObject root |
| `ViewModels/PulseBarViewModel.swift` | Refresh loop, filtering, sorting, kill confirmation |
| `Models/SystemSnapshot.swift` | System-wide metrics snapshot struct |
| `Models/ProcessRow.swift` | Process/app row data, classification, and sampled PID membership |
| `Services/DevServerDetector.swift` | Dev server heuristics |
| `Utilities/ProcessSampling.swift` | Per-process CPU/physical-footprint memory, PID tree, and port enumeration |
| `Utilities/MachHelpers.swift` | Mach API usage notes |

### Process memory reliability

PulseBar reports per-PID memory using `proc_pid_rusage(...).ri_phys_footprint`, falling back to `proc_taskinfo.pti_resident_size` only when footprint data is unavailable. Regular application rows aggregate the app's main PID plus recursive child/helper PIDs from a kernel `sysctl(KERN_PROC_ALL)` snapshot. This makes Electron, Chromium, terminal multiplexer, and helper-heavy apps line up much more closely with macOS Force Quit and Activity Monitor app totals.

---

## Extending PulseBar

**Add a new metric:**
1. Add a field to `Models/SystemSnapshot.swift`
2. Implement the query in a `Service`
3. Call it from `PulseBarViewModel.refresh()`
4. Expose via a `@Published` property and wire into a View

**Add a new process filter:**
1. Add a case to `PulseBarViewModel.Filter`
2. Implement filtering logic in the `processes` computed property
3. Bind the new option in the View

**Add a new alert rule:**
- Modify `AlertsService.evaluate()`

---

## Alert Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| Memory | > 75% | > 90% |
| CPU | ≥ 85% | — |
| Battery | ≤ 20% (not charging) | — |

---

## License

PulseBar is open source under the [GNU General Public License v3.0](LICENSE).

You are free to use, study, modify, and distribute this software. Any modified version you distribute **must also be released under the GPL-3.0** — derivative works must remain open source.
