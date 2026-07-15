import Foundation

/// Scans for running Claude Code CLI processes every few seconds and feeds
/// synthetic start/stop events into the AgentStore.
///
/// This covers *local* terminal sessions. Web/cloud sessions are tracked
/// via Claude Code hooks — see `eidos.py --setup-hooks`.
class SessionScanner {
    private let store: AgentStore
    private var timer: DispatchSourceTimer?
    private var knownPIDs: Set<Int32> = []
    private let queue = DispatchQueue(label: "com.eidos.scanner", qos: .utility)
    private let selfPID = ProcessInfo.processInfo.processIdentifier

    init(store: AgentStore) {
        self.store = store
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(500), repeating: 4.0)
        t.setEventHandler { [weak self] in self?.scan() }
        t.resume()
        timer = t
    }

    private func scan() {
        let found = Set(findClaudePIDs())

        for pid in found where !knownPIDs.contains(pid) {
            let event = AgentEvent(
                agent: "claude-session-\(pid)",
                status: "running",
                task: "Claude Code",
                progress: nil,
                elapsed: nil
            )
            store.handleEvent(event)
        }

        for pid in knownPIDs where !found.contains(pid) {
            let event = AgentEvent(
                agent: "claude-session-\(pid)",
                status: "done",
                task: nil,
                progress: 1.0,
                elapsed: nil
            )
            store.handleEvent(event)
        }

        knownPIDs = found
    }

    /// Returns PIDs of processes that look like running Claude Code sessions.
    private func findClaudePIDs() -> [Int32] {
        // pgrep -f searches the full command line, not just the process name.
        // We try two patterns: the npm package path (most specific) and the
        // bare binary name. Results are unioned so either style of install works.
        let specific = pgrepPIDs(pattern: "@anthropic-ai/claude-code")
        let binary   = pgrepPIDs(pattern: "claude").filter { isClaudeCodeProcess($0) }

        var seen = Set<Int32>()
        var result: [Int32] = []
        for pid in specific + binary {
            if seen.insert(pid).inserted { result.append(pid) }
        }
        return result
    }

    /// Runs `pgrep -f <pattern>` and returns matching PIDs, excluding self.
    private func pgrepPIDs(pattern: String) -> [Int32] {
        guard let output = run("/usr/bin/pgrep", args: ["-f", pattern]) else { return [] }
        return output
            .components(separatedBy: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 != selfPID }
    }

    /// Secondary filter for bare `claude` binary matches to weed out the Claude
    /// desktop app, grep itself, and other processes that happen to contain "claude".
    private func isClaudeCodeProcess(_ pid: Int32) -> Bool {
        // Get the executable path for this PID.
        guard let cmd = run("/bin/ps", args: ["-p", "\(pid)", "-o", "command="]) else { return false }
        let command = cmd.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Must contain "claude".
        guard command.contains("claude") else { return false }

        // Exclude things that are definitely not the Claude Code CLI.
        let excluded = ["eidos", "claude code.app", "claude.app", "/grep", "pgrep", "safari", "chrome"]
        if excluded.contains(where: { command.contains($0) }) { return false }

        // Accept if the last path component of any token is literally "claude".
        let tokens = command.split(separator: " ").map(String.init)
        return tokens.contains { ($0 as NSString).lastPathComponent == "claude" }
    }

    private func run(_ path: String, args: [String]) -> String? {
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
