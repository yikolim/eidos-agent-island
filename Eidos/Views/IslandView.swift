import SwiftUI
import AppKit

struct IslandView: View {
    @Environment(AgentStore.self) private var store
    @State private var dragStartOrigin: CGPoint?

    private var islandWindow: IslandWindow? {
        (NSApp.delegate as? AppDelegate)?.islandWindow
    }

    private var targetSize: CGSize { Self.size(for: store.islandState, agentCount: store.agents.count) }

    static func size(for state: IslandState, agentCount: Int) -> CGSize {
        switch state {
        case .idle:     return CGSize(width: 108, height: 14)
        case .mini:     return CGSize(width: 420, height: 38)
        case .cockpit:
            // Measured: header ≈ 48, each agent row ≈ 64, divider ≈ 16,
            // quick-action bar ≈ 56. Scroll only past ~6 rows.
            let rows = min(max(agentCount, 1), 6)
            return CGSize(width: 400, height: CGFloat(48 + rows * 64 + 16 + 56))
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

    /// Top corners: rounded for the compact/idle pill, but squared (0) for the
    /// expanded states so the card hangs flush from the top edge / notch.
    private var topRadius: CGFloat {
        switch store.islandState {
        case .idle, .mini: return cornerRadius
        case .cockpit, .approval: return 0
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
        // Gentle, smooth expand. The hosting view animates the window's size; the
        // window pins its top edge (IslandWindow) so it grows straight down.
        .animation(.spring(response: 0.52, dampingFraction: 0.86), value: store.islandState)
        .onHover { hovering in store.isHovered = hovering }   // hover expands the island
        .gesture(dragGesture.modifiers(.command))   // ⌘-drag to move; plain clicks never shift it
        .onTapGesture(count: 2) { islandWindow?.resetAnchor() }
        .onTapGesture { store.cycleState() }
    }

    /// Compact/idle = fully-rounded pill; expanded = squared top, rounded bottom
    /// (hangs from the notch). Matches the Dynamic Island's compact→expanded morph.
    private var islandShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: cornerRadius,
            topTrailingRadius: topRadius,
            style: .continuous
        )
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
