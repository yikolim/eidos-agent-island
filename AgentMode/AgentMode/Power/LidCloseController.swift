import Foundation

/// Opt-in "deep keep-awake": `pmset -a disablesleep 1`, which lets the Mac
/// keep running with the lid closed on battery, with no external display.
///
/// Design constraints from sections 7–8 of the brief:
///  - The app never stores an administrator password. Privileged commands run
///    through `do shell script … with administrator privileges`, so macOS
///    itself shows the auth dialog and handles credentials.
///  - The user's previous SleepDisabled value is recorded (PowerStateStore)
///    BEFORE any change and restored afterwards — including after a crash,
///    at next launch.
///  - This never touches thermal or emergency shutdown protections; those are
///    kernel-enforced and pmset disablesleep does not override them.
final class LidCloseController {
    private(set) var weDisabledSleep = false

    /// Reads the current `SleepDisabled` value from `pmset -g`.
    static func currentSleepDisabled() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return false
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return false }
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("SleepDisabled") {
                return trimmed.hasSuffix("1")
            }
        }
        return false
    }

    /// Enables lid-closed operation. Prompts for admin rights via macOS.
    /// Returns true on success.
    @discardableResult
    func enable() -> Bool {
        let previous = Self.currentSleepDisabled()
        if previous {
            // Already disabled by the user; nothing to change or restore.
            weDisabledSleep = false
            return true
        }
        PowerStateStore.savePendingRestore(
            PowerRestoreRecord(previousSleepDisabled: previous, changedAt: Date())
        )
        guard Self.runPrivileged("pmset -a disablesleep 1") else {
            PowerStateStore.clearPendingRestore()
            return false
        }
        weDisabledSleep = true
        return true
    }

    /// Restores the user's previous setting. Returns true on success.
    @discardableResult
    func disable() -> Bool {
        guard weDisabledSleep else { return true }
        guard Self.runPrivileged("pmset -a disablesleep 0") else { return false }
        weDisabledSleep = false
        PowerStateStore.clearPendingRestore()
        return true
    }

    /// Called at launch: if a previous run died after `disablesleep 1`, put
    /// the user's original setting back. Returns true if a restore happened.
    @discardableResult
    static func recoverIfNeeded() -> Bool {
        guard let record = PowerStateStore.pendingRestore() else { return false }
        guard !record.previousSleepDisabled else {
            // The user had it disabled themselves; nothing to restore.
            PowerStateStore.clearPendingRestore()
            return false
        }
        guard currentSleepDisabled() else {
            // Already back to normal (e.g. after a reboot pmset persists, but
            // the user or another tool restored it).
            PowerStateStore.clearPendingRestore()
            return false
        }
        if runPrivileged("pmset -a disablesleep 0") {
            PowerStateStore.clearPendingRestore()
            return true
        }
        return false
    }

    private static func runPrivileged(_ command: String) -> Bool {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            NSLog("AgentMode: privileged command failed: \(error)")
            return false
        }
        return true
    }
}
