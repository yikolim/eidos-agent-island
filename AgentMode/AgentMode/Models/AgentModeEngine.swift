import Foundation
import Observation

/// What the supervisor is doing right now (section 6 state flow).
enum EngineState: Equatable {
    /// Watching for agents; sleep behavior is normal.
    case idle
    /// Agents detected (or force keep-awake): the Mac is held awake.
    case active(since: Date)
    /// All agents finished; counting down the grace period before restore.
    case grace(until: Date)
    /// Keep-awake released because of the battery policy; agents may still run.
    case batteryHold
    /// Master switch off.
    case disabled

    var label: String {
        switch self {
        case .idle:        return "Waiting for agents"
        case .active:      return "Keeping Mac awake"
        case .grace:       return "Grace period"
        case .batteryHold: return "Paused — battery protection"
        case .disabled:    return "Off"
        }
    }
}

/// The supervisor: polls processes and battery, drives the sleep assertion,
/// applies grace-period + battery + failsafe policy, and emits notifications.
@Observable
final class AgentModeEngine {
    static let shared = AgentModeEngine()

    private(set) var state: EngineState = .idle
    private(set) var agents: [AgentProcess] = []
    private(set) var power = PowerSnapshot(batteryPercent: nil, onACPower: true, isCharging: false)
    private(set) var lidClosedModeEnabled = false
    /// Mirrors assertion.isActive as a tracked property so SwiftUI observes it.
    private(set) var isHoldingAwake = false
    /// Mirrors the display assertion for the UI.
    private(set) var isKeepingDisplayAwake = false
    var lastError: String?

    private let settings = AppSettings.shared
    private let monitor = ProcessMonitor()
    private let assertion = SleepAssertion()
    private let lidController = LidCloseController()
    private let scanQueue = DispatchQueue(label: "com.agentmode.scan", qos: .utility)
    private var timer: Timer?
    private var activeSince: Date?
    private var batteryNotified = false
    /// Set when the failsafe timeout fired; keep-awake stays released until
    /// the workload changes (all agents gone, or user toggles the mode).
    private var failsafeTripped = false

    static let pollInterval: TimeInterval = 3
    /// A process using at least this much CPU counts as "working".
    static let workingCPUThreshold = 2.0
    /// Below the threshold for this long → idle (waiting / possibly unfinished).
    static let idleAfter: TimeInterval = 180

    /// Per-pid last time meaningful CPU was observed.
    private var lastActive: [pid_t: Date] = [:]

    /// Agents folded to one entry per name, working groups first.
    var groups: [AgentGroup] {
        Dictionary(grouping: agents, by: \.displayName)
            .map { AgentGroup(name: $0.key, processes: $0.value) }
            .sorted {
                if $0.isWorking != $1.isWorking { return $0.isWorking }
                return $0.name < $1.name
            }
    }

    func start() {
        Notifier.shared.requestAuthorization()
        if LidCloseController.recoverIfNeeded() {
            Notifier.shared.post(.lidModeRecovered)
        }
        tick()
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Full teardown on quit: release everything and restore state (section 8).
    func shutdown() {
        timer?.invalidate()
        timer = nil
        assertion.release()
        isHoldingAwake = false
        isKeepingDisplayAwake = false
        if lidClosedModeEnabled {
            lidController.disable()
            lidClosedModeEnabled = false
        }
    }

    // MARK: - Lid-closed (privileged) mode

    func setLidClosedMode(_ on: Bool) {
        if on {
            if lidController.enable() {
                lidClosedModeEnabled = true
                lastError = nil
            } else {
                lidClosedModeEnabled = false
                lastError = "Could not enable lid-closed mode (administrator approval required)."
            }
        } else {
            if lidController.disable() {
                lidClosedModeEnabled = false
                Notifier.shared.post(.sleepRestored)
            } else {
                lastError = "Could not restore sleep settings — try again."
            }
        }
    }

    // MARK: - Poll loop

    private func tick() {
        let custom = settings.customProcessNames
        scanQueue.async { [weak self] in
            guard let self else { return }
            let scanned = self.monitor.scan(customNames: custom)
            let snapshot = BatteryMonitor.read()
            DispatchQueue.main.async {
                self.apply(scanned: scanned, snapshot: snapshot)
            }
        }
    }

    /// Stamps each process with its activity state. A process is "working"
    /// while it has used meaningful CPU within the idle window; first sight
    /// counts as active so new agents don't start out flagged as stalled.
    private func annotate(_ scanned: [AgentProcess]) -> [AgentProcess] {
        let now = Date()
        var result = scanned
        for i in result.indices {
            let pid = result[i].pid
            if result[i].cpuPercent >= Self.workingCPUThreshold || lastActive[pid] == nil {
                lastActive[pid] = now
            }
            let last = lastActive[pid] ?? now
            result[i].lastActiveAt = last
            result[i].isWorking = now.timeIntervalSince(last) < Self.idleAfter
        }
        let pids = Set(result.map(\.pid))
        lastActive = lastActive.filter { pids.contains($0.key) }
        return result
    }

    private func apply(scanned: [AgentProcess], snapshot: PowerSnapshot) {
        power = snapshot
        let scanned = annotate(scanned)
        diffGroups(old: agents, new: scanned)
        agents = scanned
        evaluate()
        // Screen keep-awake tracks both the setting and whether we're holding
        // the system awake for agents; released the moment either stops.
        assertion.setDisplayKeepAwake(
            assertion.isActive && settings.keepDisplayAwake,
            reason: "Agent Mode: keep screen on while agents work"
        )
        isKeepingDisplayAwake = assertion.isDisplayActive
    }

    /// How long a group must exist before its disappearance is worth a
    /// notification — filters the constant churn of short-lived helper
    /// processes that agents spawn (which used to fire a notification each).
    static let minRuntimeForNotification: TimeInterval = 60
    /// At most one "finished" notification per agent per this interval.
    static let notificationCooldown: TimeInterval = 120

    private var groupFirstSeen: [String: Date] = [:]
    private var lastFinishedNote: [String: Date] = [:]

    /// Notify at the whole-agent level only: a notification fires when ALL of
    /// an agent's processes are gone, and only if the agent had been around
    /// long enough to be a real run. Individual helper processes coming and
    /// going (constant with Codex/Claude Code) stay silent.
    private func diffGroups(old: [AgentProcess], new: [AgentProcess]) {
        let now = Date()
        let oldNames = Set(old.map(\.displayName))
        let newNames = Set(new.map(\.displayName))

        for name in newNames where groupFirstSeen[name] == nil {
            groupFirstSeen[name] = now
        }

        for name in oldNames.subtracting(newNames) {
            let firstSeen = groupFirstSeen.removeValue(forKey: name)
            guard let firstSeen,
                  now.timeIntervalSince(firstSeen) >= Self.minRuntimeForNotification else { continue }
            if let last = lastFinishedNote[name],
               now.timeIntervalSince(last) < Self.notificationCooldown { continue }
            lastFinishedNote[name] = now
            let started = old.filter { $0.displayName == name }
                .compactMap(\.startedAt).min() ?? firstSeen
            Notifier.shared.post(.agentFinished(
                name: name,
                runtime: AgentProcess.durationText(since: started)
            ))
        }
    }

    /// The policy core. Decides whether the assertion should be held.
    private func evaluate() {
        guard settings.agentModeEnabled || settings.forceKeepAwake else {
            failsafeTripped = false
            releaseAwake(notifyStop: false)
            state = .disabled
            return
        }

        let haveWork = !agents.isEmpty || settings.forceKeepAwake

        // Battery policy (section 11).
        if let percent = power.batteryPercent, !power.onACPower {
            let belowCutoff = percent <= settings.batteryCutoffPercent
            let chargerMissing = settings.requireCharger
            if haveWork, belowCutoff || chargerMissing {
                if assertion.isActive, !batteryNotified, belowCutoff {
                    Notifier.shared.post(.batteryThreshold(percent: percent))
                    batteryNotified = true
                }
                releaseAwake(notifyStop: false)
                state = .batteryHold
                return
            }
            if percent > settings.batteryCutoffPercent {
                batteryNotified = false
            }
        } else {
            batteryNotified = false
        }

        // Failsafe timeout (section 8): never stay awake past the limit.
        if let since = activeSince, settings.failsafeTimeout != .never,
           Date().timeIntervalSince(since) > TimeInterval(settings.failsafeTimeout.rawValue) {
            failsafeTripped = true
            releaseAwake(notifyStop: true)
            state = .idle
            return
        }
        if !haveWork { failsafeTripped = false }

        if haveWork {
            if failsafeTripped {
                state = .idle
                return
            }
            if engageAwake() {
                state = .active(since: activeSince ?? Date())
            } else {
                state = .batteryHold
            }
            return
        }

        // No work left: run the grace period (section 10).
        switch state {
        case .active:
            if settings.gracePeriod == .never {
                // Stay awake until the user turns it off.
                state = .active(since: activeSince ?? Date())
            } else if settings.gracePeriod == .immediate {
                releaseAwake(notifyStop: true)
                state = .idle
                triggerActiveSleepIfEnabled()
            } else {
                state = .grace(until: Date().addingTimeInterval(TimeInterval(settings.gracePeriod.rawValue)))
            }
        case .grace(let until):
            if Date() >= until {
                releaseAwake(notifyStop: true)
                state = .idle
                triggerActiveSleepIfEnabled()
            }
        default:
            releaseAwake(notifyStop: false)
            state = .idle
        }
    }

    // MARK: - Active sleep

    /// The "battery saver" behavior: when the last agent finishes and the
    /// grace period has run, actively put the Mac to sleep — but only on
    /// battery power, and never while any monitored agent is running.
    private func triggerActiveSleepIfEnabled() {
        guard settings.activeSleepWhenIdle, agents.isEmpty, !power.onACPower else { return }
        Notifier.shared.post(.sleepingNow)
        // Small delay so the notification lands before the machine sleeps;
        // re-check on fire in case an agent started in the meantime.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.settings.activeSleepWhenIdle, self.agents.isEmpty,
                  !self.isHoldingAwake else { return }
            Self.sleepNow()
        }
    }

    /// `pmset sleepnow` needs no privileges (unlike pmset settings changes).
    /// Falls back to a System Events AppleScript if pmset fails.
    private static func sleepNow() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["sleepnow"]
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 { return }
        } catch {
            NSLog("AgentMode: pmset sleepnow failed: \(error)")
        }
        if let script = NSAppleScript(source: "tell application \"System Events\" to sleep") {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error { NSLog("AgentMode: sleep fallback failed: \(error)") }
        }
    }

    /// Returns true if the assertion is (now) held.
    private func engageAwake() -> Bool {
        guard !assertion.isActive else {
            if activeSince == nil { activeSince = Date() }
            return true
        }
        // Refuse to start on a critically low battery (section 11).
        if let percent = power.batteryPercent, !power.onACPower,
           percent <= AppSettings.criticalBatteryPercent {
            return false
        }
        assertion.engage(reason: "Agent Mode: AI agents are working")
        isHoldingAwake = assertion.isActive
        activeSince = assertion.isActive ? Date() : nil
        return assertion.isActive
    }

    private func releaseAwake(notifyStop: Bool) {
        let wasActive = assertion.isActive
        assertion.release()
        isHoldingAwake = false
        activeSince = nil
        // One notification, not two — its body already says sleep is back.
        if wasActive, notifyStop {
            Notifier.shared.post(.agentModeStopped)
        }
    }

    // MARK: - UI helpers

    var sleepStatusText: String {
        // The assertion stays held during the grace countdown, so check
        // grace first or the countdown would never show.
        if case .grace(let until) = state {
            let remaining = max(0, Int(until.timeIntervalSinceNow))
            return "Restoring in \(remaining / 60)m \(remaining % 60)s"
        }
        if isHoldingAwake {
            var text = "Disabled while agents are active"
            if isKeepingDisplayAwake { text += " (screen on)" }
            if lidClosedModeEnabled { text += " (lid-closed OK)" }
            return text
        }
        return "Normal"
    }
}
