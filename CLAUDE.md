# Eidos — Agent Island

You are building **Eidos**: a native macOS app that puts a Dynamic Island-style floating cockpit at the top of the screen for monitoring and approving background AI agents (Codex, Claude Code, custom agents).

This is a personal dev tool, not a product. Optimize for speed and correctness, not polish. The design reference is Alcove (tryalcove.com) — a $13.99 Mac app that ports the iOS Dynamic Island to macOS. We want that same level of system-level presence but applied to AI agent supervision.

**Build everything in this repo.** All Swift goes under `Eidos/` (Xcode project), Python integration is `eidos.py` in the repo root. Read `BUILD_PLAN.md` for the full architecture diagram and phase breakdown.

---

## What you are building

A floating `NSPanel` that lives above everything at the menu bar level. It has four states:

| State | Size | Trigger |
|-------|------|---------|
| idle | 108×14px pill | No agents running |
| mini | 266×38px pill | 1+ agents running |
| cockpit | 400×240px card | 2+ agents, or user expands |
| approval | 416×298px card | Agent sent a `/approve` request |

The island transitions between states with a spring animation (`response: 0.42, dampingFraction: 0.72`). Content cross-fades. The whole thing runs without a Dock icon or menu bar item (`LSUIElement = YES`).

Agents communicate via a lightweight HTTP server embedded in the app (`localhost:7799`). The Python side is a single-file drop-in (`eidos.py`) that wraps the OpenAI Agents SDK.

---

## Tech stack

- macOS 14+ target
- Swift 5.9 / SwiftUI + AppKit hybrid
- `Network.framework` for the embedded HTTP server (no external dependencies)
- `@Observable` macro for state management
- No CocoaPods, no SPM packages (keep it dependency-free)

---

## Xcode project setup

Use `xcodegen` with `project.yml` (included in this repo). Run:

```bash
brew install xcodegen
xcodegen generate
open Eidos.xcodeproj
```

If xcodegen is unavailable, create manually: File → New Project → macOS → App, SwiftUI lifecycle, bundle ID `com.eidos.app`, deployment target macOS 14.

**Critical `Info.plist` keys:**
```xml
<key>LSUIElement</key>
<true/>
```
This hides the Dock icon and menu bar. The app is invisible except for the floating island.

---

## File structure to create

```
Eidos/
├── project.yml                    ← xcodegen config (already exists)
├── eidos.py                       ← Python integration (already exists)
├── BUILD_PLAN.md                  ← full plan (already exists)
├── CLAUDE.md                      ← this file
└── Eidos/
    ├── EidosApp.swift
    ├── Info.plist
    ├── Models/
    │   ├── AgentStore.swift
    │   ├── AgentStatus.swift
    │   ├── IslandState.swift
    │   └── AgentEvent.swift
    ├── Views/
    │   ├── IslandView.swift
    │   ├── IdleView.swift
    │   ├── MiniView.swift
    │   ├── CockpitView.swift
    │   └── ApprovalView.swift
    ├── Window/
    │   └── IslandWindow.swift
    └── Server/
        ├── IslandServer.swift
        └── ApprovalQueue.swift
```

---

## Event protocol — the full spec

All communication is HTTP/1.1 to `localhost:7799`. The Python side sends; the Swift side receives.

### POST /event
Fire-and-forget status update. Swift side ignores failures.

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

### POST /approve  (synchronous long-poll, timeout 120s)
Agent sends and BLOCKS until the user decides. Swift holds the HTTP connection open using `CheckedContinuation`.

Request body:
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

Response (sent when user taps a button):
```json
{ "approved": true,  "modified": null }
{ "approved": false, "modified": null }
{ "approved": true,  "modified": { "skip_actions": [3] } }
```

`op` values: `"edit"` | `"create"` | `"delete"` | `"run"` | `"read"` | `"open"`

### GET /status
```json
{
  "running": true,
  "agents": [{ "agent": "codex", "status": "running", "task": "Refactor auth module" }]
}
```

---

## Key Swift implementations

### EidosApp.swift
```swift
import SwiftUI
import AppKit

@main
struct EidosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var islandWindow: IslandWindow?
    let store = AgentStore()
    var server: IslandServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        islandWindow = IslandWindow(store: store)
        islandWindow?.orderFrontRegardless()
        server = IslandServer(store: store)
        server?.start()
    }
}
```

### IslandWindow.swift
```swift
import AppKit
import SwiftUI

class IslandWindow: NSPanel {
    private var hostingView: NSHostingView<IslandView>?
    private let store: AgentStore

    init(store: AgentStore) {
        self.store = store
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 266, height: 38),
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

        let view = IslandView().environment(store)
        hostingView = NSHostingView(rootView: view)
        contentView = hostingView
        reposition(width: 266, height: 38)
    }

    func reposition(width: CGFloat, height: CGFloat) {
        guard let screen = NSScreen.main else { return }
        let menuH = NSStatusBar.system.thickness
        let x = (screen.frame.width - width) / 2
        let y = screen.frame.maxY - menuH - height - 6
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

### IslandState.swift
```swift
import Foundation

enum IslandState: Equatable {
    case idle
    case mini
    case cockpit
    case approval(ApprovalRequest)
}

struct ApprovalRequest: Equatable, Identifiable, Sendable {
    let id: UUID
    let requestID: String
    let agent: String
    let task: String
    let actions: [AgentAction]

    init(id: UUID = UUID(), requestID: String, agent: String, task: String, actions: [AgentAction]) {
        self.id = id
        self.requestID = requestID
        self.agent = agent
        self.task = task
        self.actions = actions
    }
}

struct AgentAction: Equatable, Sendable {
    let op: String        // "edit" | "create" | "run" | "delete" | "read"
    let target: String
    let description: String?
}

struct ApprovalResponse: Sendable {
    let approved: Bool
    let modified: [String: Any]?
}
```

### AgentStore.swift
```swift
import Foundation
import Observation

@Observable
class AgentStore {
    var agents: [AgentStatus] = []
    var islandState: IslandState = .idle
    private var approvalQueue: [ApprovalRequest] = []

    // Called from IslandServer (background thread) — must dispatch to main
    func handleEvent(_ event: AgentEvent) {
        DispatchQueue.main.async {
            self.upsert(event)
        }
    }

    private func upsert(_ event: AgentEvent) {
        if let i = agents.firstIndex(where: { $0.agentID == event.agent }) {
            agents[i].apply(event)
            if agents[i].status == "done" || agents[i].status == "disconnected" {
                // linger 4 seconds then remove
                let id = agents[i].agentID
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    self.agents.removeAll { $0.agentID == id && $0.status == "done" }
                    self.recalcState()
                }
            }
        } else {
            agents.append(AgentStatus(from: event))
        }
        recalcState()
    }

    func pushApproval(_ req: ApprovalRequest) {
        DispatchQueue.main.async {
            self.approvalQueue.append(req)
            self.recalcState()
        }
    }

    func resolveApproval(id: String, approved: Bool, modified: [String: Any]? = nil) {
        DispatchQueue.main.async {
            self.approvalQueue.removeAll { $0.requestID == id }
            self.recalcState()
        }
    }

    func recalcState() {
        if let next = approvalQueue.first {
            islandState = .approval(next)
            return
        }
        let running = agents.filter { $0.status == "running" || $0.status == "paused" }
        switch running.count {
        case 0:  islandState = .idle
        case 1:  islandState = .mini
        default: islandState = .cockpit
        }
    }

    func cycleState() {
        switch islandState {
        case .idle:     islandState = .mini
        case .mini:     islandState = agents.isEmpty ? .idle : .cockpit
        case .cockpit:  islandState = .mini
        case .approval: islandState = .cockpit
        }
    }
}
```

### AgentStatus.swift
```swift
import Foundation

struct AgentStatus: Identifiable {
    let id = UUID()
    let agentID: String
    var status: String        // "running" | "paused" | "done" | "error"
    var task: String
    var progress: Double
    var startedAt: Date

    init(from event: AgentEvent) {
        agentID = event.agent
        status = event.status
        task = event.task ?? event.agent
        progress = event.progress ?? 0
        startedAt = Date()
    }

    mutating func apply(_ event: AgentEvent) {
        status = event.status
        if let t = event.task { task = t }
        if let p = event.progress { progress = p }
    }

    var elapsed: String {
        let s = Int(Date().timeIntervalSince(startedAt))
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m \(s % 60)s"
    }

    var color: String {
        switch agentID {
        case "codex":        return "#7c6fff"
        case "claude":       return "#cc785c"
        case "claude-code":  return "#cc785c"
        default:             return "#4ade80"
        }
    }
}
```

### AgentEvent.swift
```swift
import Foundation

struct AgentEvent: Codable, Sendable {
    let agent: String
    let status: String
    let task: String?
    let progress: Double?
    let elapsed: Int?
}

struct ApprovalRequestDTO: Codable, Sendable {
    let agent: String
    let task: String?
    let actions: [ActionDTO]
    let requestID: String?

    struct ActionDTO: Codable {
        let op: String
        let target: String
        let description: String?
    }
}
```

### IslandView.swift
```swift
import SwiftUI

struct IslandView: View {
    @Environment(AgentStore.self) private var store

    private var targetSize: CGSize {
        switch store.islandState {
        case .idle:     return CGSize(width: 108, height: 14)
        case .mini:     return CGSize(width: 266, height: 38)
        case .cockpit:  return CGSize(width: 400, height: 240)
        case .approval: return CGSize(width: 416, height: 298)
        }
    }

    private var cornerRadius: CGFloat {
        switch store.islandState {
        case .idle: return 7
        default:    return 22
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(hex: "0C0C0C"))
            islandContent
                .transition(.opacity.animation(.easeInOut(duration: 0.18)))
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: store.islandState)
        .onTapGesture { store.cycleState() }
        .onChange(of: store.islandState) { _, new in
            // Resize the window to match the new island size
            if let app = NSApp.delegate as? AppDelegate {
                app.islandWindow?.reposition(width: targetSize.width, height: targetSize.height)
            }
        }
    }

    @ViewBuilder
    private var islandContent: some View {
        switch store.islandState {
        case .idle:
            IdleView()
        case .mini:
            MiniView()
        case .cockpit:
            CockpitView()
        case .approval(let req):
            ApprovalView(request: req)
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
```

### IdleView.swift
```swift
import SwiftUI

struct IdleView: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(dotColor(i))
                    .frame(width: 5, height: 5)
                    .opacity(phase ? 0.9 : 0.25)
                    .animation(
                        .easeInOut(duration: 1.6).repeatForever().delay(Double(i) * 0.35),
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
    }

    func dotColor(_ i: Int) -> Color {
        [Color(hex: "7c6fff"), Color(hex: "4ade80"), Color(hex: "faad14")][i]
    }
}
```

### MiniView.swift
```swift
import SwiftUI

struct MiniView: View {
    @Environment(AgentStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(store.agents.prefix(2).enumerated()), id: \.offset) { _, agent in
                agentChip(agent)
            }
            if store.agents.count > 2 {
                Divider()
                    .frame(height: 18)
                    .background(Color.white.opacity(0.1))
            }
            Spacer()
            let running = store.agents.filter { $0.status == "running" }.count
            Text("\(running) running")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 14)
    }

    func agentChip(_ agent: AgentStatus) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: agent.color))
                .frame(width: 6, height: 6)
                .opacity(agent.status == "running" ? 1 : 0.4)
            Text(agent.agentID.capitalized)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
```

### CockpitView.swift
```swift
import SwiftUI

struct CockpitView: View {
    @Environment(AgentStore.self) private var store
    @State private var tick = false
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ACTIVE AGENTS")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(0.8)
                Spacer()
                Button(action: { store.islandState = .mini }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .frame(width: 18, height: 18)
                .background(.white.opacity(0.07))
                .clipShape(Circle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 12)

            ForEach(store.agents) { agent in
                agentRow(agent)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 5)
            }

            Divider().background(.white.opacity(0.07)).padding(.horizontal, 16).padding(.vertical, 8)

            HStack(spacing: 6) {
                quickAction("pause all", icon: "pause.fill") { }
                quickAction("approvals", icon: "bell") {
                    if case .approval(let r) = store.islandState { } // noop if no approval
                }
                quickAction("settings", icon: "gear") { }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
        .onReceive(timer) { _ in tick.toggle() }
    }

    func agentRow(_ agent: AgentStatus) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(hex: agent.color).opacity(0.15))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: agentIcon(agent.agentID))
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: agent.color))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.task)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                Text("\(agent.agentID) · \(agent.elapsed)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.07)).frame(height: 2)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: agent.color))
                            .frame(width: geo.size.width * agent.progress, height: 2)
                            .animation(.easeInOut(duration: 0.8), value: agent.progress)
                    }
                }
                .frame(height: 2)
                .padding(.top, 3)
            }

            statusBadge(agent.status)
        }
        .padding(10)
        .background(.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    func statusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = switch status {
        case "running": ("running", Color(hex: "4ade80"))
        case "paused":  ("paused",  Color(hex: "faad14"))
        case "done":    ("done",    .white.opacity(0.3))
        default:        ("error",   Color(hex: "f87171"))
        }
        return Text(label)
            .font(.system(size: 10))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    func quickAction(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 11))
            }
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    func agentIcon(_ id: String) -> String {
        switch id {
        case "codex":       return "cpu"
        case "claude", "claude-code": return "bolt.circle"
        default:            return "terminal"
        }
    }
}
```

### ApprovalView.swift
```swift
import SwiftUI

struct ApprovalView: View {
    let request: ApprovalRequest
    @Environment(AgentStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header badge
            HStack(spacing: 5) {
                Circle().fill(Color(hex: "faad14")).frame(width: 5, height: 5)
                    .opacity(0.9)
                Text("APPROVAL NEEDED")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "faad14"))
                    .tracking(0.3)
            }
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Color(hex: "faad14").opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.bottom, 10)

            Text(request.task)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
            Text("\(request.agent) · step \(request.actions.count) actions pending")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.bottom, 12)

            // Action preview
            VStack(alignment: .leading, spacing: 5) {
                Text("PENDING ACTIONS")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.25))
                    .tracking(0.6)
                    .padding(.bottom, 2)

                ForEach(Array(request.actions.enumerated()), id: \.offset) { _, action in
                    HStack(alignment: .top, spacing: 7) {
                        opBadge(action.op)
                        Text(action.target)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }
            .padding(11)
            .background(.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.bottom, 12)

            // Buttons
            HStack(spacing: 7) {
                Button(action: { resolve(approved: true) }) {
                    Label("Approve", systemImage: "checkmark")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "4ade80"))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color(hex: "4ade80").opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: { resolve(approved: true) }) {  // modify = approve with note for now
                    Text("Modify")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: { resolve(approved: false) }) {
                    Text("Reject")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    func opBadge(_ op: String) -> some View {
        let (label, color): (String, Color) = switch op {
        case "edit":   ("edit",   Color(hex: "7c6fff"))
        case "create": ("create", Color(hex: "4ade80"))
        case "run":    ("run",    Color(hex: "faad14"))
        case "delete": ("delete", Color(hex: "f87171"))
        default:       (op,       .white.opacity(0.4))
        }
        return Text(label)
            .font(.system(size: 9))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    func resolve(approved: Bool) {
        store.resolveApproval(id: request.requestID, approved: approved)
        // TODO: signal IslandServer.ApprovalQueue to resume the continuation
        NotificationCenter.default.post(
            name: .approvalResolved,
            object: nil,
            userInfo: ["requestID": request.requestID, "approved": approved]
        )
    }
}

extension Notification.Name {
    static let approvalResolved = Notification.Name("approvalResolved")
}
```

### IslandServer.swift
```swift
import Foundation
import Network

class IslandServer {
    private var listener: NWListener?
    private let store: AgentStore
    private let queue = DispatchQueue(label: "com.eidos.server", qos: .userInitiated)
    let approvalQueue = ApprovalQueue()

    init(store: AgentStore) {
        self.store = store
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(approvalResolved(_:)),
            name: .approvalResolved,
            object: nil
        )
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: 7799)
            listener?.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    print("IslandServer failed: \(error)")
                }
            }
            listener?.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            listener?.start(queue: queue)
            print("IslandServer listening on :7799")
        } catch {
            print("IslandServer start error: \(error)")
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receiveHTTP(conn)
    }

    private func receiveHTTP(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            guard let data, !data.isEmpty else { return }

            let raw = String(data: data, encoding: .utf8) ?? ""
            let lines = raw.components(separatedBy: "\r\n")
            guard let requestLine = lines.first else { return }
            let parts = requestLine.components(separatedBy: " ")
            guard parts.count >= 2 else { return }
            let method = parts[0]
            let path = parts[1]

            // Extract JSON body (everything after the blank line)
            let body: Data
            if let bodyRange = raw.range(of: "\r\n\r\n") {
                let bodyStr = String(raw[bodyRange.upperBound...])
                body = bodyStr.data(using: .utf8) ?? Data()
            } else {
                body = Data()
            }

            self.route(method: method, path: path, body: body, conn: conn)
        }
    }

    private func route(method: String, path: String, body: Data, conn: NWConnection) {
        switch (method, path) {
        case ("POST", "/event"):
            handleEvent(body: body)
            respond(conn: conn, status: 200, body: #"{"ok":true}"#)

        case ("POST", "/approve"):
            handleApprove(body: body, conn: conn)  // does NOT respond immediately

        case ("GET", "/status"):
            let agents = store.agents.map { ["agent": $0.agentID, "status": $0.status] }
            let json = try? JSONSerialization.data(withJSONObject: ["running": true, "agents": agents])
            respond(conn: conn, status: 200, body: String(data: json ?? Data(), encoding: .utf8) ?? "{}")

        default:
            respond(conn: conn, status: 404, body: #"{"error":"not found"}"#)
        }
    }

    private func handleEvent(body: Data) {
        guard let event = try? JSONDecoder().decode(AgentEvent.self, from: body) else { return }
        store.handleEvent(event)
    }

    private func handleApprove(body: Data, conn: NWConnection) {
        guard let dto = try? JSONDecoder().decode(ApprovalRequestDTO.self, from: body) else {
            respond(conn: conn, status: 400, body: #"{"error":"bad request"}"#)
            return
        }
        let reqID = dto.requestID ?? UUID().uuidString
        let actions = dto.actions.map { AgentAction(op: $0.op, target: $0.target, description: $0.description) }
        let req = ApprovalRequest(requestID: reqID, agent: dto.agent, task: dto.task ?? dto.agent, actions: actions)

        // Register the connection so we can respond when the user decides
        approvalQueue.register(requestID: reqID, connection: conn)
        store.pushApproval(req)
        // Connection stays open — ApprovalQueue resumes it via approvalResolved(_:)
    }

    @objc private func approvalResolved(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reqID = info["requestID"] as? String,
              let approved = info["approved"] as? Bool else { return }
        approvalQueue.resolve(requestID: reqID, approved: approved)
    }

    func respond(conn: NWConnection, status: Int, body: String) {
        let response = "HTTP/1.1 \(status) OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n\(body)"
        conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
```

### ApprovalQueue.swift
```swift
import Foundation
import Network

// Holds open HTTP connections for /approve long-polls
// When the user resolves, we write the JSON response and close the connection
class ApprovalQueue {
    private var pending: [String: NWConnection] = [:]
    private let lock = NSLock()

    func register(requestID: String, connection: NWConnection) {
        lock.lock(); defer { lock.unlock() }
        pending[requestID] = connection
    }

    func resolve(requestID: String, approved: Bool, modified: Any? = nil) {
        lock.lock()
        let conn = pending.removeValue(forKey: requestID)
        lock.unlock()

        guard let conn else { return }

        var body: [String: Any] = ["approved": approved, "modified": NSNull()]
        if let m = modified { body["modified"] = m }
        let json = (try? JSONSerialization.data(withJSONObject: body)).flatMap { String(data: $0, encoding: .utf8) } ?? #"{"approved":false}"#

        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(json.utf8.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n\(json)"
        conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
```

---

## Build order

Build in this exact order. Each step is testable before moving to the next.

1. **Create the Xcode project** using `xcodegen generate` with `project.yml`, or manually.
2. **Phase 1**: Implement `IslandWindow.swift` + `IslandView.swift` + all 4 sub-views with hardcoded mock data. Run the app. The island should float above the menu bar. Click to cycle states. Verify spring animation feels right.
3. **Phase 2**: Implement `AgentStore.swift`, `AgentStatus.swift`, `IslandState.swift`. Wire all views to the store. Test with `store.cycleState()` calls.
4. **Phase 3**: Implement `IslandServer.swift` (just `/event` first). Test with:
   ```bash
   curl -X POST http://localhost:7799/event \
     -H 'Content-Type: application/json' \
     -d '{"agent":"codex","status":"running","task":"Refactor auth","progress":0.4,"elapsed":30}'
   ```
   The island should switch from idle to mini.
5. **Phase 4**: Add `/approve` + `ApprovalQueue.swift`. Test with:
   ```bash
   curl -X POST http://localhost:7799/approve \
     -H 'Content-Type: application/json' \
     -d '{"agent":"codex","task":"Edit files","actions":[{"op":"edit","target":"auth.ts"}]}'
   ```
   This should block until you tap approve/reject in the island.
6. **Phase 5**: Wire Python `eidos.py` to a real Codex agent. See full end-to-end.

---

## Testing each phase

After each phase, test before moving on.

**Phase 1 smoke test:**
- App launches with no Dock icon
- Island appears near the top center of the screen
- Clicking the island cycles through all 4 states
- Spring animation looks right (slight overshoot on expand)

**Phase 3 smoke test (curl):**
```bash
# Agent starts
curl -X POST http://localhost:7799/event -H 'Content-Type: application/json' \
  -d '{"agent":"codex","status":"running","task":"Building feature X","progress":0.0}'

# Progress update
sleep 2
curl -X POST http://localhost:7799/event -H 'Content-Type: application/json' \
  -d '{"agent":"codex","status":"running","task":"Building feature X","progress":0.65}'

# Agent done
sleep 2
curl -X POST http://localhost:7799/event -H 'Content-Type: application/json' \
  -d '{"agent":"codex","status":"done","progress":1.0}'
```

**Phase 4 smoke test (approval):**
```bash
curl -X POST http://localhost:7799/approve -H 'Content-Type: application/json' \
  -d '{
    "agent": "codex",
    "task": "Update config files",
    "actions": [
      {"op": "edit",   "target": "config/app.ts"},
      {"op": "run",    "target": "npm install dotenv"},
      {"op": "create", "target": "config/.env.example"}
    ]
  }'
# This curl command should BLOCK until you tap Approve or Reject in the island
# Then it should print the JSON response and exit
```

---

## Known edge cases to handle

- App launch: `NSApp.setActivationPolicy(.accessory)` must be called before any windows are shown
- Screen changes: listen to `NSApplication.didChangeScreenParametersNotification` and reposition the island
- Multiple approval requests: queue them, show one at a time, advance when resolved
- Server already running: catch `EADDRINUSE` from `NWListener`, show a user-facing error or pick a different port
- Python side unavailable (island not running): `eidos.py` catches all `httpx` exceptions and silently continues — agents should not fail because the island is off

---

## What NOT to do

- Do not use `NSStatusItem` (menu bar icon) — this app has no visible menu bar presence, that's intentional
- Do not use `URLSession` as the HTTP server — use `Network.framework` directly
- Do not add any Swift Package Manager dependencies — stay dependency-free
- Do not use `@EnvironmentObject` — use `@Observable` + `@Environment` (modern SwiftUI)
- Do not animate the window frame using AppKit's `animate: true` — let SwiftUI handle the sizing via `.frame()` and animate the panel reposition separately with no animation

---

## Final goal

After all phases complete, you should be able to run:

```python
from agents import Agent, Runner
from eidos import IslandHook, approval_tool

agent = Agent(
    name="Codex",
    instructions="""
    You are a coding assistant. Before writing to any files or running shell commands,
    you MUST call request_approval with a list of the actions you want to take.
    Only proceed after approval is granted.
    """,
    hooks=IslandHook("codex"),
    tools=[approval_tool("codex"), write_file_tool, run_command_tool],
)

Runner.run_sync(agent, "Add JWT refresh token support to the auth module")
```

And see the island appear, show progress, expand for approval when the agent wants to write files, and continue after you tap approve.
