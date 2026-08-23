import Foundation
import Observation

/// How long the Mac stays available after the last monitored agent exits.
enum GracePeriod: Int, CaseIterable, Identifiable, Codable {
    case immediate = 0
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case never = -1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .immediate:      return "Immediately"
        case .fiveMinutes:    return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes:  return "30 minutes"
        case .never:          return "Never automatically"
        }
    }
}

/// Failsafe: never keep the Mac awake longer than this, no matter what.
enum FailsafeTimeout: Int, CaseIterable, Identifiable, Codable {
    case fourHours = 14400
    case eightHours = 28800
    case twelveHours = 43200
    case twentyFourHours = 86400
    case never = -1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fourHours:       return "4 hours"
        case .eightHours:      return "8 hours"
        case .twelveHours:     return "12 hours"
        case .twentyFourHours: return "24 hours"
        case .never:           return "Never"
        }
    }
}

/// User preferences, persisted to UserDefaults on every change.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// Master switch: watch for agents and auto-manage sleep.
    var agentModeEnabled: Bool { didSet { save() } }
    /// Keep the Mac awake even with no detected agents.
    var forceKeepAwake: Bool { didSet { save() } }
    var gracePeriod: GracePeriod { didSet { save() } }
    var failsafeTimeout: FailsafeTimeout { didSet { save() } }
    /// Stop keeping the Mac awake below this battery % (when on battery power).
    var batteryCutoffPercent: Int { didSet { save() } }
    /// Only keep awake while the charger is connected.
    var requireCharger: Bool { didSet { save() } }
    /// Actively put the Mac to sleep once the last agent finishes (and the
    /// grace period expires) while on battery power. Never fires while any
    /// monitored agent is still running.
    var activeSleepWhenIdle: Bool { didSet { save() } }
    /// Extra process-name substrings (lowercased match) the user wants monitored.
    var customProcessNames: [String] { didSet { save() } }
    var notificationsEnabled: Bool { didSet { save() } }
    var launchAtLogin: Bool { didSet { save() } }

    /// Below this level Agent Mode refuses to engage at all.
    static let criticalBatteryPercent = 10

    private static let key = "com.agentmode.settings"

    private struct Snapshot: Codable {
        var agentModeEnabled: Bool
        var forceKeepAwake: Bool
        var gracePeriod: GracePeriod
        var failsafeTimeout: FailsafeTimeout
        var batteryCutoffPercent: Int
        var requireCharger: Bool
        // Optional so snapshots saved by older builds still decode.
        var activeSleepWhenIdle: Bool?
        var customProcessNames: [String]
        var notificationsEnabled: Bool
        var launchAtLogin: Bool
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            agentModeEnabled = s.agentModeEnabled
            forceKeepAwake = s.forceKeepAwake
            gracePeriod = s.gracePeriod
            failsafeTimeout = s.failsafeTimeout
            batteryCutoffPercent = s.batteryCutoffPercent
            requireCharger = s.requireCharger
            activeSleepWhenIdle = s.activeSleepWhenIdle ?? false
            customProcessNames = s.customProcessNames
            notificationsEnabled = s.notificationsEnabled
            launchAtLogin = s.launchAtLogin
        } else {
            agentModeEnabled = true
            forceKeepAwake = false
            gracePeriod = .fiveMinutes
            failsafeTimeout = .twelveHours
            batteryCutoffPercent = 20
            requireCharger = false
            activeSleepWhenIdle = false
            customProcessNames = []
            notificationsEnabled = true
            launchAtLogin = false
        }
    }

    private func save() {
        let s = Snapshot(
            agentModeEnabled: agentModeEnabled,
            forceKeepAwake: forceKeepAwake,
            gracePeriod: gracePeriod,
            failsafeTimeout: failsafeTimeout,
            batteryCutoffPercent: batteryCutoffPercent,
            requireCharger: requireCharger,
            activeSleepWhenIdle: activeSleepWhenIdle,
            customProcessNames: customProcessNames,
            notificationsEnabled: notificationsEnabled,
            launchAtLogin: launchAtLogin
        )
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
