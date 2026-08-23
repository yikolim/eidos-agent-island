import Foundation
import Darwin

/// Scans the process table with libproc/sysctl and identifies agent processes.
///
/// Detection strategy (section 9 of the brief):
///   1. Match the executable name / path against known agent signatures
///      (claude, codex, openclaw, cursor-agent, aider).
///   2. For interpreter processes (node, bun, python, deno) inspect argv via
///      sysctl(KERN_PROCARGS2) — Claude Code and Codex often run as node/bun.
///   3. Match any user-configured custom substrings.
final class ProcessMonitor {

    struct Signature {
        let displayName: String
        /// Lowercased substrings matched against the executable name or path.
        let nameMatches: [String]
    }

    static let builtinSignatures: [Signature] = [
        Signature(displayName: "Claude Code", nameMatches: ["claude"]),
        Signature(displayName: "Codex", nameMatches: ["codex"]),
        Signature(displayName: "OpenClaw", nameMatches: ["openclaw"]),
        Signature(displayName: "Cursor Agent", nameMatches: ["cursor-agent"]),
        Signature(displayName: "Aider", nameMatches: ["aider"]),
    ]

    /// Interpreter executables whose argv is worth inspecting.
    private static let interpreters: Set<String> = ["node", "bun", "python", "python3", "deno"]

    /// Previous CPU-time samples, keyed by pid, for CPU% deltas.
    private var lastSamples: [pid_t: (cpuTimeNs: UInt64, at: Date)] = [:]

    /// One full scan of the process table. Runs off the main thread.
    func scan(customNames: [String]) -> [AgentProcess] {
        let custom = customNames
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        let ownPid = ProcessInfo.processInfo.processIdentifier

        // Size the buffer from the live process table (plus headroom for churn).
        let needed = Int(proc_listallpids(nil, 0))
        var pids = [pid_t](repeating: 0, count: max(4096, needed + 256))
        // proc_listallpids returns the number of PIDs written (not bytes).
        let pidCount = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard pidCount > 0 else { return [] }
        let count = min(Int(pidCount), pids.count)

        var found: [AgentProcess] = []
        var seenPids = Set<pid_t>()

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0, pid != ownPid, !seenPids.contains(pid) else { continue }

            let name = Self.processName(pid: pid).lowercased()
            let path = Self.processPath(pid: pid).lowercased()
            guard !name.isEmpty || !path.isEmpty else { continue }

            var display: String?

            for sig in Self.builtinSignatures {
                if sig.nameMatches.contains(where: { name.contains($0) || path.hasSuffix("/\($0)") }) {
                    display = sig.displayName
                    break
                }
            }

            if display == nil, Self.interpreters.contains(name) {
                if let args = Self.processArguments(pid: pid) {
                    let joined = args.joined(separator: " ").lowercased()
                    for sig in Self.builtinSignatures {
                        if sig.nameMatches.contains(where: { joined.contains($0) }) {
                            display = sig.displayName
                            break
                        }
                    }
                    if display == nil, let match = custom.first(where: { joined.contains($0) }) {
                        display = match
                    }
                }
            }

            if display == nil, let match = custom.first(where: { name.contains($0) }) {
                display = match.capitalized
            }

            guard let displayName = display else { continue }
            seenPids.insert(pid)

            let usage = Self.resourceUsage(pid: pid)
            var cpuPercent = 0.0
            let now = Date()
            if let usage {
                if let prev = lastSamples[pid] {
                    let dt = now.timeIntervalSince(prev.at)
                    if dt > 0.5, usage.cpuTimeNs >= prev.cpuTimeNs {
                        cpuPercent = Double(usage.cpuTimeNs - prev.cpuTimeNs) / (dt * 1e9) * 100
                    }
                }
                lastSamples[pid] = (usage.cpuTimeNs, now)
            }

            found.append(AgentProcess(
                pid: pid,
                displayName: displayName,
                processName: name,
                startedAt: Self.startTime(pid: pid),
                cpuPercent: cpuPercent,
                memoryBytes: usage?.memoryBytes ?? 0
            ))
        }

        lastSamples = lastSamples.filter { seenPids.contains($0.key) }
        return found.sorted { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    // MARK: - libproc / sysctl helpers

    private static func processName(pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let n = proc_name(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return "" }
        return String(cString: buf)
    }

    private static func processPath(pid: pid_t) -> String {
        // PROC_PIDPATHINFO_MAXSIZE (4*MAXPATHLEN) is a macro Swift won't import.
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return "" }
        return String(cString: buf)
    }

    private static func startTime(pid: pid_t) -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        // p_starttime is a C macro for p_un.__p_starttime; macros aren't imported.
        let tv = info.kp_proc.p_un.__p_starttime
        guard tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6)
    }

    /// ri_user_time/ri_system_time are in mach_absolute_time units, not ns.
    private static let timebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()

    private static func resourceUsage(pid: pid_t) -> (cpuTimeNs: UInt64, memoryBytes: UInt64)? {
        var usage = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &usage) { ptr in
            ptr.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
            }
        }
        guard result == 0 else { return nil }
        let ticks = usage.ri_user_time + usage.ri_system_time
        let ns = ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
        return (ns, usage.ri_phys_footprint)
    }

    /// argv of a process via sysctl(KERN_PROCARGS2). Only works for processes
    /// owned by the current user, which is exactly the set we care about.
    private static func processArguments(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > 4 else { return nil }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0 else { return nil }

        var args: [String] = []
        var index = MemoryLayout<Int32>.size

        // Skip the executable path.
        while index < size, buffer[index] != 0 { index += 1 }
        // Skip padding NULs.
        while index < size, buffer[index] == 0 { index += 1 }

        var current: [UInt8] = []
        while index < size, args.count < Int(argc) {
            if buffer[index] == 0 {
                args.append(String(decoding: current, as: UTF8.self))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(buffer[index])
            }
            index += 1
        }
        return args
    }
}
