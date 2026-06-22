import SwiftUI
import AppKit

struct IslandView: View {
    @Environment(AgentStore.self) private var store
    @State private var dragStartOrigin: CGPoint?

    private var islandWindow: IslandWindow? {
        (NSApp.delegate as? AppDelegate)?.islandWindow
    }

    private var targetSize: CGSize {
        switch store.islandState {
        case .idle:     return CGSize(width: 108, height: 14)
        case .mini:     return CGSize(width: 420, height: 38)
        case .cockpit:
            // Measured: header ≈ 48, each agent row ≈ 64, divider ≈ 16,
            // quick-action bar ≈ 56. Scroll only past ~6 rows.
            let rows = min(max(store.agents.count, 1), 6)
            let height = CGFloat(48 + rows * 64 + 16 + 56)
            return CGSize(width: 400, height: height)
        case .approval: return CGSize(width: 416, height: 298)
        }
    }

    private var cornerRadius: CGFloat {
        switch store.islandState {
        case .idle:     return 7    // small pill
        case .mini:     return 19   // half-height = full pill
        case .cockpit:  return 28
        case .approval: return 30
        }
    }

    var body: some View {
        ZStack {
            islandShape
                .fill(Color(hex: "0C0C0C"))
            islandContent
                // Content fades in/out fast and tracks the morph (no staged delay).
                .transition(.opacity.animation(.easeInOut(duration: 0.14)))
        }
        .frame(width: targetSize.width, height: targetSize.height)
        // Fluid, gooey expand like the iOS Dynamic Island / Alcove: a clearly
        // bouncy spring that overshoots and settles, not a flat ease.
        .animation(.spring(response: 0.55, dampingFraction: 0.6), value: store.islandState)
        // Window sizing + centering is handled in IslandWindow (the hosting view
        // resizes the window to fit this frame; the window re-centers on resize).
        .onHover { hovering in store.isHovered = hovering }   // hover expands the island
        .gesture(dragGesture.modifiers(.command))   // ⌘-drag to move; plain clicks never shift it
        .onTapGesture(count: 2) { islandWindow?.resetAnchor() }
        .onTapGesture { store.cycleState() }
    }

    /// A fully-rounded pill/rounded-rect (continuous corners) — the Dynamic
    /// Island shape, rather than a squared-top card.
    private var islandShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// Drag the whole island to reposition it. A small minimum distance keeps
    /// single taps (cycle) and double taps (recenter) working normally.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                guard let window = islandWindow else { return }
                let start = dragStartOrigin ?? window.frame.origin
                if dragStartOrigin == nil { dragStartOrigin = start }
                // SwiftUI's global space is top-left origin; AppKit window
                // origin is bottom-left — so invert the vertical translation.
                let origin = CGPoint(
                    x: start.x + value.translation.width,
                    y: start.y - value.translation.height
                )
                window.dragStartActive = true
                window.dragTo(origin: origin)
            }
            .onEnded { _ in
                dragStartOrigin = nil
                islandWindow?.dragStartActive = false
            }
    }

    @ViewBuilder
    private var islandContent: some View {
        switch store.islandState {
        case .idle:
            IdleView()
        case .mini:
            MiniView()
        case .cockpit:
            CockpitView()
        case .approval(let req):
            ApprovalView(request: req)
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
