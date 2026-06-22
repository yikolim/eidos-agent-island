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
        reposition(width: 108, height: 14)   // idle size
    }

    /// Set true by the view while a ⌘-drag is in progress (so the drag positions
    /// the window freely without the anchor override fighting it).
    var dragStartActive = false

    /// Enforce TOP-CENTER anchoring on EVERY frame change — including the
    /// hosting view's animated resizes as the island grows/shrinks. Without
    /// this, AppKit keeps the bottom-left origin so the window grows upward
    /// (off the top of the screen) and then snaps back, which reads as the
    /// island expanding from its middle. Anchoring the top edge makes it grow
    /// straight down from y=0 (the notch), tracking the SwiftUI spring smoothly.
    /// Reposition a proposed frame so its TOP edge and horizontal center stay at
    /// the anchor, regardless of the size AppKit/the hosting view chose.
    private func anchored(_ frameRect: NSRect) -> NSRect {
        guard !dragStartActive, let screen = NSScreen.main else { return frameRect }
        let anchor = anchorTopCenter ?? defaultAnchor(on: screen)
        var f = frameRect
        f.origin.x = anchor.x - f.size.width / 2          // horizontally centered
        f.origin.y = anchor.y - f.size.height             // top edge pinned to anchor
        let s = screen.frame
        f.origin.x = min(max(f.origin.x, s.minX), s.maxX - f.size.width)
        f.origin.y = min(max(f.origin.y, s.minY), s.maxY - f.size.height)
        return f
    }

    // The hosting view animates the window's SIZE as the island grows/shrinks.
    // Every resize path keeps the bottom-left origin by default (window grows
    // upward, then content sits centered → looks like it expands from the
    // middle). Re-anchor the top edge on ALL of them so it grows straight down.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(anchored(frameRect), display: flag)
    }
    override func setFrame(_ frameRect: NSRect, display: Bool, animate: Bool) {
        super.setFrame(anchored(frameRect), display: display, animate: animate)
    }
    override func setContentSize(_ size: NSSize) {
        super.setContentSize(size)
        super.setFrame(anchored(frame), display: true)
    }

    /// Position the island at a given size (origin is enforced by `anchored`).
    func reposition(width: CGFloat, height: CGFloat, centered: Bool = false) {
        super.setFrame(anchored(NSRect(x: 0, y: 0, width: width, height: height)), display: true)
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
