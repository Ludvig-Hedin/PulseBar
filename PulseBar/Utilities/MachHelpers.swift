// Placeholder if you want to split lower-level Mach wrappers later.

import Foundation

// Keep empty for v1. The app already works without a separate helper layer.

// XCODE / PROJECT SETTINGS
// 1) Signing & Capabilities
//    - App Sandbox: OFF for local dev utility builds.
//      Why: task_for_pid, lsof, and process inspection are painful or blocked in sandboxed builds.
//      If you want Mac App Store later, expect a redesign of process inspection.
//
// 2) Deployment target
//    - macOS 14+ minimum is reasonable.
//    - If you target the latest system only, even better.
//
// 3) Info.plist
//    - Application is agent (UIElement): YES if you want menu bar only and no dock icon.
//      If you still want the dashboard window reachable easily while developing, keep it NO first.
//
// 4) Recommended v1 behavior
//    - Keep dock icon during dev.
//    - After stable, switch to agent app.
//
// WHAT THIS VERSION ALREADY DOES
// - Real system CPU usage via host_processor_info
// - Real memory totals/usage via host_statistics64 + physical memory
// - Real battery state via IOKit power APIs
// - Real network throughput via getifaddrs delta sampling
// - Running process list via NSWorkspace / NSRunningApplication
// - Graceful quit and force quit
// - Dev server detection by executable/path/ports
// - Visible ports in the process table
// - Alerts for memory pressure, CPU runaway, low battery
// - Native menu bar + dashboard UX with system materials
//
// IMPORTANT REALITY CHECK
// The weak spot is per-process CPU/memory sampling.
// task_for_pid is the clean route for deep per-process inspection, but permissions can bite.
// For a local power-user utility on your own Mac, that is acceptable.
// For a polished distributed app, you will need stronger permission handling and fallbacks.
//
// If you want the next pass, the right move is not more features.
// The right move is:
// 1) split this into actual files,
// 2) compile-fix,
// 3) add permission/failure fallbacks,
// 4) add port-based quick filters,
// 5) add a proper "dev servers only" dashboard panel.
