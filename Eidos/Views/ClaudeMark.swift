import SwiftUI

/// The Claude "sunburst" mark — radial tapered rays from a common center.
/// A clean geometric stand-in (not the trademarked asset) rendered in the
/// Claude rust color. Optionally "breathes" while active to signal running.
struct ClaudeMark: View {
    var color: Color = Color(hex: "cc785c")
    var active: Bool = false
    private let rayCount = 12

    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(0..<rayCount, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: s * 0.13, height: s * 0.5)
                        .offset(y: -s * 0.25)          // push each ray outward…
                        .rotationEffect(.degrees(Double(i) / Double(rayCount) * 360))
                }
            }
            .frame(width: s, height: s)
            .scaleEffect(active ? (pulse ? 1.0 : 0.84) : 1.0)
            .opacity(active ? (pulse ? 1.0 : 0.7) : 1.0)
            .animation(
                active ? .easeInOut(duration: 0.95).repeatForever(autoreverses: true) : .default,
                value: pulse
            )
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .onAppear { pulse = true }
    }

    static func matches(_ agentID: String) -> Bool {
        agentID == "claude" || agentID == "claude-code" || agentID.hasPrefix("claude-session-")
    }
}
