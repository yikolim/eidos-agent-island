import SwiftUI

struct MiniView: View {
    @Environment(AgentStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(store.agents.prefix(2).enumerated()), id: \.offset) { _, agent in
                agentChip(agent)
            }
            if store.agents.count > 2 {
                Divider()
                    .frame(height: 18)
                    .background(Color.white.opacity(0.1))
            }
            Spacer()
            let running = store.agents.filter { $0.status == "running" }.count
            Text("\(running) running")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 14)
    }

    func agentChip(_ agent: AgentStatus) -> some View {
        HStack(spacing: 5) {
            if ClaudeMark.matches(agent.agentID) {
                ClaudeMark(color: Color(hex: agent.color), active: agent.status == "running")
                    .frame(width: 12, height: 12)
            } else {
                PulseDot(color: Color(hex: agent.color), active: agent.status == "running")
            }
            Text(agent.agentID.capitalized)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
