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
