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

    private func apply(scanned: [AgentProcess], snapshot: PowerSnapshot) {
        power = snapshot
        diffAgents(old: agents, new: scanned)
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

    private func diffAgents(old: [AgentProcess], new: [AgentProcess]) {
        let newPids = Set(new.map(\.pid))
        for gone in old where !newPids.contains(gone.pid) {
            if new.isEmpty {
                Notifier.shared.post(.agentFinished(name: gone.displayName, runtime: gone.runtimeText))
            } else {
                // Others still running — flag it, since we can't read the exit
                // status of a non-child process (section 12: crashed/disappeared).
                Notifier.shared.post(.agentDisappeared(name: gone.displayName))
            }
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
        if wasActive, notifyStop {
            Notifier.shared.post(.agentModeStopped)
            Notifier.shared.post(.sleepRestored)
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
