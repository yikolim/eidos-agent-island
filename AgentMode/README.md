# Agent Mode

> Close your Mac. Your agents keep working.

A native macOS menu-bar app that turns a Mac into an always-on machine for AI
agents and long-running development tasks. It detects agent processes (Claude
Code, Codex, OpenClaw, Cursor Agent, Aider, or anything you add), keeps the
Mac awake **only while they're working**, protects the battery, notifies you
when work finishes, and automatically restores normal sleep behavior.

Built from `Agent_Mode_Product_Brief` — an agent-aware runtime supervisor,
not a keep-awake toggle.

## Requirements

- macOS 14+ (Sonoma), Apple Silicon first
- Swift 5.9 / SwiftUI `MenuBarExtra`
- Zero dependencies (no SPM packages, no CocoaPods)

## Build

With Xcode:

```bash
cd AgentMode
brew install xcodegen   # if needed
xcodegen generate
open AgentMode.xcodeproj
```

Or with just the Command Line Tools:

```bash
cd AgentMode
./build.sh --run
```

## How it works

| Layer | Mechanism |
|---|---|
| Sleep control | `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep)` — supported, unprivileged, auto-released by the kernel if the app dies |
| Lid-closed mode (opt-in) | `pmset -a disablesleep 1` via `do shell script … with administrator privileges` — macOS shows the auth dialog; the app never sees or stores a password |
| State safety | Previous `SleepDisabled` value is written to `~/Library/Application Support/AgentMode/power-restore.json` **before** any change and restored on stop, quit, or — after a crash — at next launch |
| Agent detection | `proc_listallpids` / `proc_pidpath` / `proc_name`, plus `sysctl(KERN_PROCARGS2)` argv inspection for interpreter processes (node, bun, python, deno), polled every 3 s |
| Resource stats | `proc_pid_rusage` — CPU % from time deltas, memory from `ri_phys_footprint` |
| Smart sleep | Grace period after the last agent exits: immediately / 5 / 15 / 30 min / never (default 5 min) |
| Battery | IOKit power-source snapshot; configurable cutoff (default 20 %), optional require-charger, hard floor at 10 % |
| Failsafe | Never stays awake longer than a configurable limit (default 12 h), even if a process wedges |
| Notifications | `UserNotifications`: agent finished, agent disappeared, battery threshold, mode stopped, sleep restored, crash recovery |
| Launch at login | `SMAppService.mainApp` |

### State flow

```
agent starts → Agent Mode activates → user leaves / closes lid
     → process continues → agent exits → grace period
     → previous sleep state restored → notification
```

### Safety guarantees (brief §8)

- The unprivileged keep-awake is a process-scoped IOPM assertion — if the app
  crashes or is force-quit, the kernel releases it. The Mac can never be left
  stuck awake by that path.
- The privileged path (`disablesleep`) records the prior state to disk first.
  On every launch the app checks for an unrestored record and puts the user's
  setting back (with one admin prompt), then notifies.
- Thermal and emergency shutdown protections are never touched.
- Agent Mode refuses to engage below 10 % battery on battery power.

## MVP acceptance test (brief §18)

1. Launch Agent Mode (menu-bar bolt/moon icon appears; no Dock icon).
2. Start Claude Code with a long-running task: the icon switches to a filled
   bolt within ~3 s and the menu shows `Claude Code — Running — Nm`.
3. Optionally enable **Lid-closed mode** (admin prompt) and close the lid.
4. Let the task finish: notification fires, grace period counts down in the
   menu, then sleep is restored and a second notification confirms it.
5. Quit the app mid-session: sleep settings are restored on the way out.
6. `kill -9` the app mid-session with lid-closed mode on: relaunch restores
   the prior `pmset` state and posts a "settings recovered" notification.

Quick smoke test without a real agent: in Settings add a custom process
substring that matches something you can run on demand (e.g. add `yes` and run
`yes > /dev/null` in Terminal), or simply toggle **Keep awake even with no
agents** in the menu.

Verify the assertion is actually held:

```bash
pmset -g assertions | grep -A2 AgentMode
```

## Source layout

```
AgentMode/
├── project.yml                  ← xcodegen config
├── build.sh                     ← swiftc-only build
└── AgentMode/
    ├── AgentModeApp.swift       ← @main, MenuBarExtra, app delegate, login item
    ├── Info.plist
    ├── Models/
    │   ├── AgentModeEngine.swift  ← supervisor state machine (poll → policy → assert)
    │   ├── AgentProcess.swift
    │   └── AppSettings.swift
    ├── Power/
    │   ├── SleepAssertion.swift   ← IOPMAssertion wrapper
    │   ├── LidCloseController.swift ← privileged pmset path + crash recovery
    │   ├── PowerStateStore.swift  ← restore-record persistence
    │   └── BatteryMonitor.swift   ← IOKit power snapshot
    ├── Processes/
    │   └── ProcessMonitor.swift   ← libproc/sysctl agent detection
    ├── Notifications/
    │   └── Notifier.swift
    └── Views/
        ├── MenuView.swift         ← menu-bar dropdown (status, agents, controls)
        └── SettingsView.swift
```

## Roadmap (from the brief)

- **Phase 2 — Agent Supervisor**: richer multi-agent dashboard, working/idle/
  waiting states, aggregate resource usage, auto-restart after failure.
- **Phase 3 — Remote monitoring**: iPhone/web status via an encrypted relay,
  remote stop/approve with strong authentication.
