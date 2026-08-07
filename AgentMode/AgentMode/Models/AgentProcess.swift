import Foundation

/// A detected agent process and its live resource stats.
struct AgentProcess: Identifiable, Equatable {
    let pid: pid_t
    /// Friendly name shown in the UI ("Claude Code", "Codex", …).
    let displayName: String
    /// Raw executable name (proc_name).
    let processName: String
    let startedAt: Date?
    var cpuPercent: Double
    var memoryBytes: UInt64

    var id: pid_t { pid }

    var runtimeText: String {
        guard let startedAt else { return "—" }
        let s = Int(Date().timeIntervalSince(startedAt))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60) min" }
        return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
    }

    var memoryText: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }
}
