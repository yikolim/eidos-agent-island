import SwiftUI

/// A small dot that blinks on/off — used to signal active "running" state.
/// Distinct from PulseDot's gentle breathing: this is a sharper on↔off blink.
struct BlinkingDot: View {
    var color: Color = Color(hex: "4ade80")   // green
    var size: CGFloat = 6
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(on ? 1 : 0.18)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
