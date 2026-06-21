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
        case .mini:     return CGSize(width: 266, height: 38)
        case .cockpit:  return CGSize(width: 400, height: 240)
        case .approval: return CGSize(width: 416, height: 298)
        }
    }

    private var bottomRadius: CGFloat {
        switch store.islandState {
        case .idle:     return 10
        case .mini:     return 19
        case .cockpit:  return 24
        case .approval: return 24
        }
    }

    var body: some View {
        ZStack {
            islandShape
                .fill(Color(hex: "0C0C0C"))
            islandContent
                .transition(.opacity.animation(.easeInOut(duration: 0.18)))
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: store.islandState)
        .gesture(dragGesture.modifiers(.command))   // ⌘-drag to move; plain clicks never shift it
        .onTapGesture(count: 2) { islandWindow?.resetAnchor() }
        .onTapGesture { store.cycleState() }
        .onChange(of: store.islandState) { _, _ in
            // Resize the window to match the new island size. Approvals always
            // snap back to the top-center notch so they're never off to a side.
            let centerIt: Bool = { if case .approval = store.islandState { return true }; return false }()
            islandWindow?.reposition(width: targetSize.width, height: targetSize.height, centered: centerIt)
        }
    }

    /// Squared top, rounded bottom — so the island looks like it hangs from the
    /// top edge of the screen (the Dynamic Island shape) rather than a floating card.
    private var islandShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0,
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
                window.dragTo(origin: origin)
            }
            .onEnded { _ in dragStartOrigin = nil }
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
