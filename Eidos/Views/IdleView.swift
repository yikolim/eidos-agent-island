import SwiftUI

struct IdleView: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(dotColor(i))
                    .frame(width: 5, height: 5)
                    .opacity(phase ? 0.9 : 0.25)
                    .animation(
                        .easeInOut(duration: 1.6).repeatForever().delay(Double(i) * 0.35),
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
    }

    func dotColor(_ i: Int) -> Color {
        [Color(hex: "7c6fff"), Color(hex: "4ade80"), Color(hex: "faad14")][i]
    }
}
