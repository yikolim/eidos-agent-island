import SwiftUI
import AppKit

@main
struct EidosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var islandWindow: IslandWindow?
    let store = AgentStore()
    var server: IslandServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Default is .accessory (no Dock icon / menu bar — the intended mode).
        // EIDOS_DEBUG_REGULAR=1 runs as a regular app so screen-automation tools
        // that only enumerate regular apps can see and drive the island. Does not
        // affect normal runs.
        if ProcessInfo.processInfo.environment["EIDOS_DEBUG_REGULAR"] == "1" {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }

        islandWindow = IslandWindow(store: store)
        islandWindow?.orderFrontRegardless()

        server = IslandServer(store: store)
        server?.start()

        // Reposition the island when the screen layout changes (resolution,
        // display arrangement, notch, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged() {
        islandWindow?.repositionForCurrentState()
    }
}
