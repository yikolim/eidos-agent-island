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
    /// Last time this process used meaningful CPU (maintained by the engine).
    var lastActiveAt: Date = Date()
    /// Actively working (recent CPU) vs idle/waiting/possibly abandoned.
    var isWorking: Bool = true

    var id: pid_t { pid }

    var runtimeText: String { Self.durationText(since: startedAt) }

    var memoryText: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }

    static func durationText(since date: Date?) -> String {
        guard let date else { return "—" }
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60) min" }
        return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
    }
}

/// One agent as the user thinks of it: all its processes (parents, helpers,
/// children) folded into a single row.
struct AgentGroup: Identifiable {
    let name: String
    let processes: [AgentProcess]

    var id: String { name }

    /// Working if ANY member process is working.
    var isWorking: Bool { processes.contains { $0.isWorking } }
    var totalCPU: Double { processes.reduce(0) { $0 + $1.cpuPercent } }
    var totalMemoryBytes: UInt64 { processes.reduce(0) { $0 + $1.memoryBytes } }
    var oldestStart: Date? { processes.compactMap(\.startedAt).min() }
    var lastActiveAt: Date? { processes.map(\.lastActiveAt).max() }

    var runtimeText: String { AgentProcess.durationText(since: oldestStart) }
    var idleForText: String { AgentProcess.durationText(since: lastActiveAt) }
    var memoryText: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalMemoryBytes), countStyle: .memory)
    }
}
