# Third-Party Licenses

PulseBar's Storage / Cleaning subsystem is adapted from open-source code. The
following licenses cover that adapted material.

---

## PureMac

PulseBar's Storage architecture — the actor-based scan engine, location database,
Full Disk Access detection, and AppleScript admin-escalation flow — is adapted
from PureMac (https://github.com/momenbasel/PureMac).

```
MIT License

Copyright (c) 2024 Momen Basel

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Files derived from PureMac

The following PulseBar files adapt PureMac concepts and patterns. Each carries a
top-of-file attribution comment.

- `PulseBar/Services/Cleaner/Locations.swift`
- `PulseBar/Services/Cleaner/PathAllowlist.swift`
- `PulseBar/Services/Cleaner/ScanEngine.swift`
- `PulseBar/Services/Cleaner/CategoryScanner.swift`
- `PulseBar/Services/Cleaner/FullDiskAccessDetector.swift`
- `PulseBar/Services/Cleaner/CleanupService.swift`
- `PulseBar/Models/StorageCategory.swift`

The implementations differ from PureMac (Trash-first by default, narrower
admin-escalation allowlist, hardened shell-argument validation, AsyncStream-
based progress reporting), but the architectural shape and category set
originate there.
