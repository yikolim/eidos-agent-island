import SwiftUI

/// A small status dot that gently "breathes" (scale + opacity) while active.
/// Used to signal a live/running agent without being distracting.
struct PulseDot: View {
    let color: Color
    var active: Bool = true
    var size: CGFloat = 6
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(active ? (pulse ? 1.18 : 0.86) : 1.0)
            .opacity(active ? (pulse ? 1.0 : 0.5) : 0.4)
            .animation(
                active
                    ? .easeInOut(duration: 0.95).repeatForever(autoreverses: true)
                    : .default,
                value: pulse
            )
            .onAppear { pulse = true }
    }
}
