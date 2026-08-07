import Foundation
import IOKit.pwr_mgt

/// Wraps a single IOPMAssertion that prevents idle system sleep.
///
/// This is the supported, unprivileged mechanism (section 7). It keeps the
/// system awake while the lid is open, and in clamshell mode when an external
/// display and power are connected. Kernel-level lid-closed-on-battery
/// operation requires `pmset disablesleep` — see LidCloseController.
///
/// The assertion is process-scoped: if the app crashes or is force-quit, the
/// kernel releases it automatically, so this layer can never leave the Mac
/// stuck awake (section 8).
final class SleepAssertion {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    func engage(reason: String) {
        guard !isActive else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        isActive = (result == kIOReturnSuccess)
        if !isActive {
            NSLog("AgentMode: failed to create sleep assertion (\(result))")
        }
    }

    func release() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }

    deinit { release() }
}
