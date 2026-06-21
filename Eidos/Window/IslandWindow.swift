import AppKit
import SwiftUI

class IslandWindow: NSPanel {
    private var hostingView: NSHostingView<AnyView>?
    private let store: AgentStore

    /// Where the island is pinned, expressed as its TOP-CENTER point in screen
    /// coordinates. `nil` means "use the default" (centered under the menu bar).
    /// Once the user drags the island, this holds their chosen spot so that
    /// state/size changes grow the panel from the same anchor instead of
    /// snapping back to center.
    private var anchorTopCenter: CGPoint?

    init(store: AgentStore) {
        self.store = store
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 266, height: 38),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above the menu bar (which sits at .statusBar) so the island can hang
        // from the very top edge / notch without being clipped by it.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false

        let view = IslandView().environment(store)
        hostingView = NSHostingView(rootView: AnyView(view))
        contentView = hostingView
        reposition(width: 266, height: 38)

        // The hosting view auto-resizes the window to fit the SwiftUI content,
        // but that resize keeps the bottom-left origin — so mini→cockpit grew
        // rightward off-center. Re-center on every resize to correct it.
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResizeNotif),
            name: NSWindow.didResizeNotification, object: self
        )
    }

    private var isRepositioning = false

    /// Re-center whenever the hosting view resizes the window (unless the user is
    /// mid ⌘-drag). Guarded against the resize our own `setFrame` triggers.
    @objc private func windowDidResizeNotif() {
        guard !isRepositioning, dragStartActive == false else { return }
        let centered: Bool = { if case .approval = store.islandState { return true }; return false }()
        let s = frame.size
        reposition(width: s.width, height: s.height, centered: centered)
    }

    /// Set true by the view while a ⌘-drag is in progress so resizes don't fight it.
    var dragStartActive = false

    /// Position the island. When `centered` is true the drag anchor is ignored
    /// and it snaps back to the top-center notch — used for important states
    /// (approvals) that should always be front-and-center.
    func reposition(width: CGFloat, height: CGFloat, centered: Bool = false) {
        guard let screen = NSScreen.main else { return }
        isRepositioning = true
        defer { isRepositioning = false }
        let anchor = (centered ? nil : anchorTopCenter) ?? defaultAnchor(on: screen)

        var x = anchor.x - width / 2
        var y = anchor.y - height   // anchor.y is the top edge; origin is bottom-left

        // Keep the panel fully on-screen.
        let f = screen.frame
        x = min(max(x, f.minX), f.maxX - width)
        y = min(max(y, f.minY), f.maxY - height)

        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: false)
    }

    /// Top-center, flush with the very top edge of the screen so the island
    /// hangs from the notch like a real Dynamic Island (the window level is
    /// raised above the menu bar so this isn't clipped).
    private func defaultAnchor(on screen: NSScreen) -> CGPoint {
        CGPoint(x: screen.frame.midX, y: screen.frame.maxY)
    }

    /// Move the panel to a new bottom-left origin while dragging, and remember
    /// the resulting top-center as the anchor so future resizes respect it.
    func dragTo(origin: CGPoint) {
        setFrameOrigin(origin)
        let f = frame
        anchorTopCenter = CGPoint(x: f.midX, y: f.maxY)
    }

    /// Reset to the default centered position (e.g. a double-click affordance).
    func resetAnchor() {
        anchorTopCenter = nil
        repositionForCurrentState()
    }

    /// Re-positions the panel using its current size. Used when the screen
    /// configuration changes (resolution, display arrangement, etc.).
    func repositionForCurrentState() {
        let size = frame.size
        reposition(width: size.width, height: size.height)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
