import SwiftUI
import AppKit
import ServiceManagement

@main
struct AgentModeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    private let engine = AgentModeEngine.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(engine)
        } label: {
            MenuBarLabel(engine: engine)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(engine)
        }
    }
}

/// Menu bar icon: filled bolt while holding the Mac awake, moon otherwise.
struct MenuBarLabel: View {
    let engine: AgentModeEngine

    var body: some View {
        // The assertion stays held during the grace countdown, so the grace
        // state must win over isHoldingAwake or its icon would never show.
        if case .grace = engine.state {
            Image(systemName: "bolt.badge.clock")
        } else if engine.isHoldingAwake {
            Image(systemName: "bolt.circle.fill")
        } else {
            Image(systemName: "moon.zzz")
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AgentModeEngine.shared.start()
    }

    // Section 8: restore everything BEFORE termination proceeds. Doing it here
    // rather than in applicationWillTerminate matters for lid-closed mode,
    // whose restore shows an admin prompt — willTerminate gives no time for
    // that. shutdown() is idempotent, so the willTerminate backup is safe.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AgentModeEngine.shared.shutdown()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        AgentModeEngine.shared.shutdown()
    }
}

enum LoginItem {
    @discardableResult
    static func set(enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("AgentMode: launch-at-login change failed: \(error)")
            return false
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
