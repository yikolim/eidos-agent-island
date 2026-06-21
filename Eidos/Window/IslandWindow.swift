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
        level = .statusBar
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
    }

    /// Position the island. When `centered` is true the drag anchor is ignored
    /// and it snaps back to the top-center notch — used for important states
    /// (approvals) that should always be front-and-center.
    func reposition(width: CGFloat, height: CGFloat, centered: Bool = false) {
        guard let screen = NSScreen.main else { return }
        let anchor = (centered ? nil : anchorTopCenter) ?? defaultAnchor(on: screen)

        var x = anchor.x - width / 2
        var y = anchor.y - height   // anchor.y is the top edge; origin is bottom-left

        // Keep the panel fully on-screen.
        let f = screen.frame
        x = min(max(x, f.minX), f.maxX - width)
        y = min(max(y, f.minY), f.maxY - height)

        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: false)
    }

    /// Top-center, hanging from the BOTTOM edge of the menu bar so the whole
    /// island sits below the notch/sensor area and nothing is clipped — the
    /// equivalent of Apple's rule that Dynamic Island content flanks the camera
    /// rather than sitting under it. `visibleFrame.maxY` is just under the menu bar.
    private func defaultAnchor(on screen: NSScreen) -> CGPoint {
        CGPoint(x: screen.frame.midX, y: screen.visibleFrame.maxY)
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
