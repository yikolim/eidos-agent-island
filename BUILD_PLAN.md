# Eidos — Agent Island build plan

macOS Dynamic Island-style cockpit for AI agents. Native Swift/SwiftUI. First integration: OpenAI Agents SDK (Codex).

---

## Architecture overview

```
┌─────────────────────────────────┐
│   macOS  (Swift / SwiftUI)      │
│                                 │
│   NSPanel @ statusBar level     │
│   ┌──────────────────────────┐  │
│   │  IslandView (SwiftUI)    │  │
│   │  state machine:          │  │
│   │  idle → mini → cockpit   │  │
│   │              → approval  │  │
│   └──────────────────────────┘  │
│                                 │
│   IslandServer                  │
│   localhost:7799                │
│   POST /event                   │
│   POST /approve  (long-poll)    │
│   GET  /status                  │
└─────────────┬───────────────────┘
              │  JSON over HTTP
┌─────────────▼───────────────────┐
│   Python  (OpenAI Agents SDK)   │
│                                 │
│   IslandHook  (RunHooks)        │
│   ApprovalTool (function_tool)  │
│   eidos.py  (single file drop-  │
│             in for any agent)   │
└─────────────────────────────────┘
```

---

## Event protocol (the contract between app and agents)

All communication is newline-delimited JSON over HTTP to `localhost:7799`.

### POST /event
Agent sends a status update. Fire and forget — the island ignores failures silently.

```json
{
  "agent":    "codex",
  "status":   "running",
  "task":     "Refactor auth module",
  "progress": 0.68,
  "elapsed":  142
}
```

`status` values: `"running"` | `"paused"` | `"done"` | `"error"` | `"disconnected"`

### POST /approve  (synchronous, long-poll up to 120s)
Agent sends a list of actions and blocks until the user approves, modifies, or rejects.

Request:
```json
{
  "agent":   "codex",
  "task":    "Refactor auth module",
  "actions": [
    { "op": "edit",   "target": "src/auth/jwt.ts",        "description": "Replace HS256 with RS256" },
    { "op": "edit",   "target": "src/middleware/session.ts" },
    { "op": "create", "target": "src/auth/refresh.ts" },
    { "op": "run",    "target": "npm install jsonwebtoken@9" }
  ]
}
```

Response (when user decides):
```json
{ "approved": true,  "modified": null }
{ "approved": false, "modified": null }
{ "approved": true,  "modified": { "skip_actions": [3] } }
```

`op` values: `"edit"` | `"create"` | `"delete"` | `"run"` | `"read"` | `"open"`

### GET /status
Returns the current state of all connected agents. Used by the Python side to check connectivity.

```json
{
  "running": true,
  "agents": [
    { "agent": "codex", "status": "running", "task": "Refactor auth module" }
  ]
}
```

---

## Phase 1 — Island window + all 4 views (mock data)
Goal: see the island floating on screen with real spring animations. No server yet, just hardcoded data.

### Xcode project setup
- New macOS App target, SwiftUI lifecycle
- `Info.plist`: set `LSUIElement` to `YES` (no Dock icon, no menu bar icon)
- Bundle ID: `com.yourname.eidos`

### IslandWindow.swift
```swift
import AppKit
import SwiftUI

class IslandWindow: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        contentView = NSHostingView(rootView: IslandView())
    }

    func reposition(width: CGFloat, height: CGFloat) {
        guard let screen = NSScreen.main else { return }
        let menuH = NSApp.mainMenu?.menuBarHeight ?? 24
        let x = (screen.frame.width - width) / 2
        let y = screen.frame.maxY - menuH - height - 6
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: false)
    }
}
```

### IslandState.swift
```swift
enum IslandState: Equatable {
    case idle
    case mini
    case cockpit
    case approval(ApprovalRequest)
}

struct ApprovalRequest: Equatable, Identifiable {
    let id = UUID()
    let agent: String
    let task: String
    let actions: [AgentAction]
}

struct AgentAction: Equatable {
    let op: String      // "edit" | "create" | "run" | "delete"
    let target: String
    let description: String?
}
```

### AgentStatus.swift
```swift
@Observable
class AgentStore {
    var agents: [AgentStatus] = []
    var islandState: IslandState = .idle
    var pendingApproval: ApprovalRequest? = nil

    func upsert(_ event: AgentEvent) {
        if let i = agents.firstIndex(where: { $0.id == event.agent }) {
            agents[i].update(from: event)
        } else {
            agents.append(AgentStatus(from: event))
        }
        recalcState()
    }

    func recalcState() {
        if let req = pendingApproval {
            islandState = .approval(req)
        } else if agents.filter({ $0.status == "running" }).isEmpty {
            islandState = .idle
        } else if agents.count == 1 {
            islandState = .mini
        } else {
            islandState = .cockpit
        }
    }
}
```

### IslandView.swift (the core SwiftUI view)
```swift
struct IslandView: View {
    @Environment(AgentStore.self) var store

    var targetSize: CGSize {
        switch store.islandState {
        case .idle:     return CGSize(width: 108, height: 14)
        case .mini:     return CGSize(width: 266, height: 38)
        case .cockpit:  return CGSize(width: 400, height: 240)
        case .approval: return CGSize(width: 416, height: 298)
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(hex: "0C0C0C"))

            content
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: store.islandState)
        .onTapGesture { store.cycleState() }
    }

    var cornerRadius: CGFloat {
        switch store.islandState {
        case .idle: return 7
        default:    return 22
        }
    }

    @ViewBuilder
    var content: some View {
        switch store.islandState {
        case .idle:            IdleView()
        case .mini:            MiniView()
        case .cockpit:         CockpitView()
        case .approval(let r): ApprovalView(request: r)
        }
    }
}
```

### Sub-views (build each in its own file)
- `IdleView.swift` — 3 breathing dots with staggered opacity animation
- `MiniView.swift` — agent name chips, "N running" count
- `CockpitView.swift` — agent rows with progress bars, quick action buttons
- `ApprovalView.swift` — approval badge, action preview list, 3 buttons

---

## Phase 2 — AgentStore + live state machine
Goal: island responds correctly to multiple agents, queues approvals.

Key logic in `AgentStore.recalcState()`:
- 0 running agents → `.idle`
- 1 running agent, no pending approvals → `.mini`
- 2+ running agents, no pending approvals → `.cockpit`
- Any pending approval → `.approval(request)` (takes priority)

Also add:
- Elapsed time counter: each `AgentStatus` has a `startedAt: Date` and a 1-second timer publishes updates
- Auto-dismiss `.done` agents after 5 seconds
- Approval queue (array) — show one at a time, advance when resolved

---

## Phase 3 — Embedded HTTP server
Goal: accept events and approval requests from the Python side.

Use `Network.framework` — no external dependencies needed.

```swift
import Network

class IslandServer {
    let port: UInt16 = 7799
    var listener: NWListener?
    var store: AgentStore

    func start() {
        let params = NWParameters.tcp
        listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener?.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener?.start(queue: .global())
    }

    func handle(_ conn: NWConnection) {
        // read HTTP request, parse JSON body, route to /event or /approve
        // For /approve: store a continuation, resume it when user decides
    }
}
```

For the `/approve` long-poll, use `CheckedContinuation`:
```swift
var pendingApprovals: [UUID: CheckedContinuation<ApprovalResponse, Never>] = [:]

func requestApproval(_ req: ApprovalRequest) async -> ApprovalResponse {
    return await withCheckedContinuation { continuation in
        pendingApprovals[req.id] = continuation
        DispatchQueue.main.async {
            self.store.pendingApproval = req
        }
    }
}

func resolveApproval(id: UUID, response: ApprovalResponse) {
    pendingApprovals[id]?.resume(returning: response)
    pendingApprovals[id] = nil
    DispatchQueue.main.async {
        self.store.pendingApproval = nil
        self.store.recalcState()
    }
}
```

---

## Phase 4 — Python integration (eidos.py)
Goal: single-file drop-in for any OpenAI Agents SDK project.

```python
# eidos.py — drop this in your project, import and use
import json, threading, time
from typing import Any
import httpx
from agents import RunHooks, AgentHooks, RunContextWrapper, Agent, Tool, FunctionTool
from agents.lifecycle import AgentHooks

ISLAND_URL = "http://localhost:7799"

class IslandHook(AgentHooks):
    """
    Drop-in hook for OpenAI Agents SDK.
    Usage:
        agent = Agent(name="Codex", hooks=IslandHook("codex"), ...)
    """
    def __init__(self, agent_id: str):
        self.agent_id = agent_id
        self._client = httpx.Client(timeout=2.0)
        self._start_time = None

    def _post_event(self, status: str, **kwargs):
        try:
            self._client.post(f"{ISLAND_URL}/event", json={
                "agent": self.agent_id,
                "status": status,
                "elapsed": int(time.time() - self._start_time) if self._start_time else 0,
                **kwargs
            })
        except Exception:
            pass  # island might not be running, that's fine

    def on_start(self, context: RunContextWrapper, agent: Agent) -> None:
        self._start_time = time.time()
        task = str(agent.instructions)[:80] if agent.instructions else agent.name
        self._post_event("running", task=task, progress=0.0)

    def on_end(self, context: RunContextWrapper, agent: Agent, output: Any) -> None:
        self._post_event("done", progress=1.0)

    def on_tool_start(self, context: RunContextWrapper, agent: Agent, tool: Tool) -> None:
        self._post_event("running", task=f"Using {tool.name}")

    def on_handoff(self, context: RunContextWrapper, agent: Agent, source: Agent) -> None:
        self._post_event("running", task=f"Handed off from {source.name}")


def approval_tool(agent_id: str = "agent"):
    """
    Returns a function_tool that pauses execution and asks the user via the island.

    Usage:
        agent = Agent(
            name="Codex",
            tools=[approval_tool("codex"), ...],
        )
    """
    def request_approval(actions: list[dict]) -> dict:
        """
        Request user approval before executing a list of actions.
        Each action: {"op": "edit"|"create"|"run"|"delete", "target": str, "description": str}
        Returns: {"approved": bool, "modified": dict | None}
        """
        try:
            resp = httpx.post(
                f"{ISLAND_URL}/approve",
                json={"agent": agent_id, "actions": actions},
                timeout=120.0
            )
            return resp.json()
        except Exception:
            # island not running — auto-approve (or raise, your choice)
            return {"approved": True, "modified": None}

    return FunctionTool(
        name="request_approval",
        description="Request user approval before executing file edits, shell commands, or other actions. Always call this before writing files or running commands.",
        params_json_schema={
            "type": "object",
            "properties": {
                "actions": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "op": {"type": "string", "enum": ["edit", "create", "delete", "run", "read"]},
                            "target": {"type": "string"},
                            "description": {"type": "string"}
                        },
                        "required": ["op", "target"]
                    }
                }
            },
            "required": ["actions"]
        },
        on_invoke_tool=lambda ctx, args_str: request_approval(json.loads(args_str)["actions"])
    )
```

### Usage example
```python
from agents import Agent, Runner
from eidos import IslandHook, approval_tool

agent = Agent(
    name="Codex",
    instructions="You are a coding assistant. Before editing any files, always call request_approval.",
    hooks=IslandHook("codex"),
    tools=[
        approval_tool("codex"),
        # ... your other tools
    ]
)

result = Runner.run_sync(agent, "Refactor the auth module to use RS256")
```

---

## Phase 5 — Wire + polish
- Keyboard shortcuts: `Cmd+Shift+A` to summon/dismiss, `Return` to approve, `Esc` to reject
- Auto-hide island when no active agents (with a 3-second linger after `.done`)
- Notification dot on idle state when approval is queued
- Multiple approval queue — cycle through with arrow keys or swipe
- Swipe gesture on island: swipe right = approve, swipe left = reject

---

## File structure

```
Eidos/
├── Eidos.xcodeproj
└── Eidos/
    ├── EidosApp.swift           # App entry point, window setup
    ├── Info.plist               # LSUIElement = YES
    ├── Models/
    │   ├── AgentStore.swift     # @Observable, source of truth
    │   ├── AgentStatus.swift    # per-agent state
    │   ├── IslandState.swift    # state enum + ApprovalRequest
    │   └── AgentEvent.swift     # Codable DTO from HTTP
    ├── Views/
    │   ├── IslandView.swift     # root view, state router
    │   ├── IdleView.swift
    │   ├── MiniView.swift
    │   ├── CockpitView.swift
    │   └── ApprovalView.swift
    ├── Window/
    │   └── IslandWindow.swift   # NSPanel subclass
    └── Server/
        ├── IslandServer.swift   # NWListener, HTTP parse
        └── ApprovalQueue.swift  # continuation management

eidos.py                         # Python drop-in (single file)
```

---

## Build order (fastest path to working end-to-end)

1. `IslandWindow` + hardcoded `IslandView` with all 4 states — click to cycle. Validate feel.
2. `AgentStore` + `IslandState` — wire views to real data model.
3. `IslandServer` — `POST /event` only. Test with `curl -d '{"agent":"codex","status":"running","task":"test"}' http://localhost:7799/event`.
4. `eidos.py` `IslandHook` — run a real Codex agent, see status appear.
5. `/approve` endpoint + `ApprovalView` wired to resolve the continuation.
6. `approval_tool` in Python — full end-to-end: agent asks, island shows, user taps, agent continues.

---

## Estimated time (personal dev tool pace)

| Phase | What | Time |
|-------|------|------|
| 1 | Window + 4 views (mock) | ~4h |
| 2 | AgentStore + state machine | ~2h |
| 3 | HTTP server + /event | ~3h |
| 4 | Python IslandHook | ~1h |
| 5 | /approve + ApprovalView wired | ~3h |
| 6 | eidos.py approval_tool + e2e test | ~2h |
| **Total** | | **~15h** |
