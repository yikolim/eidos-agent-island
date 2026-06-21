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
    var scanner: SessionScanner?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["EIDOS_DEBUG_REGULAR"] == "1" {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }

        islandWindow = IslandWindow(store: store)
        islandWindow?.orderFrontRegardless()

        server = IslandServer(store: store)
        server?.start()

        scanner = SessionScanner(store: store)
        scanner?.start()

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
