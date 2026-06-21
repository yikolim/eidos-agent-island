import Foundation

class SessionScanner {
    private let store: AgentStore
    private var timer: DispatchSourceTimer?
    private var knownPIDs: [Int32: SessionInfo] = [:]
    private let queue = DispatchQueue(label: "com.eidos.scanner", qos: .utility)

    struct SessionInfo {
        let pid: Int32
        let cwd: String?
        let startedAt: Date
    }

    init(store: AgentStore) {
        self.store = store
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 3.0)
        t.setEventHandler { [weak self] in self?.scan() }
        t.resume()
        timer = t
    }

    private func scan() {
        let found = findClaudeSessions()
        let foundPIDs = Set(found.map(\.pid))

        for session in found where knownPIDs[session.pid] == nil {
            knownPIDs[session.pid] = session
            let label = sessionLabel(session)
            let event = AgentEvent(
                agent: agentID(session.pid),
                status: "running",
                task: label,
                progress: nil,
                elapsed: nil
            )
            store.handleEvent(event)
        }

        for pid in knownPIDs.keys where !foundPIDs.contains(pid) {
            knownPIDs.removeValue(forKey: pid)
            let event = AgentEvent(
                agent: agentID(pid),
                status: "done",
                task: nil,
                progress: 1.0,
                elapsed: nil
            )
            store.handleEvent(event)
        }
    }

    private func agentID(_ pid: Int32) -> String {
        "claude-session-\(pid)"
    }

    private func sessionLabel(_ session: SessionInfo) -> String {
        if let cwd = session.cwd {
            let dir = (cwd as NSString).lastPathComponent
            return "Session in \(dir)"
        }
        return "Claude Code session"
    }

    private func findClaudeSessions() -> [SessionInfo] {
        guard let output = shell("/bin/ps", args: ["-eo", "pid,command"]) else { return [] }

        var results: [SessionInfo] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let pid = parsePID(trimmed) else { continue }
            guard isClaudeCodeCommand(trimmed) else { continue }
            let cwd = processCWD(pid)
            results.append(SessionInfo(pid: pid, cwd: cwd, startedAt: Date()))
        }
        return results
    }

    private func parsePID(_ line: String) -> Int32? {
        let parts = line.split(separator: " ", maxSplits: 1)
        guard let first = parts.first else { return nil }
        return Int32(first)
    }

    private func isClaudeCodeCommand(_ line: String) -> Bool {
        let lower = line.lowercased()
        guard lower.contains("claude") else { return false }
        if lower.contains("eidos") { return false }
        if lower.contains("/bin/ps") { return false }
        if lower.contains("grep") { return false }
        if lower.contains("pgrep") { return false }

        if lower.contains("@anthropic-ai/claude-code") { return true }
        if lower.contains("claude-code/cli") { return true }

        let parts = line.split(separator: " ")
        for part in parts {
            let p = String(part)
            let base = (p as NSString).lastPathComponent
            if base == "claude" { return true }
        }

        return false
    }

    private func processCWD(_ pid: Int32) -> String? {
        guard let output = shell("/usr/sbin/lsof", args: ["-p", "\(pid)", "-Fn"]) else { return nil }
        var foundCwd = false
        for line in output.components(separatedBy: "\n") {
            if line == "fcwd" { foundCwd = true; continue }
            if foundCwd, line.hasPrefix("n") {
                return String(line.dropFirst())
            }
        }
        return nil
    }

    private func shell(_ path: String, args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
