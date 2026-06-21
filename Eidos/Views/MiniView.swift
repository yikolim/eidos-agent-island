import SwiftUI

struct MiniView: View {
    @Environment(AgentStore.self) private var store

    private var claudeSessions: [AgentStatus] {
        store.agents.filter { $0.isClaudeAgent && $0.status == "running" }
    }

    private var otherAgents: [AgentStatus] {
        store.agents.filter { !$0.isClaudeAgent }
    }

    var body: some View {
        HStack(spacing: 8) {
            if !claudeSessions.isEmpty {
                claudeSessionChip
            }
            ForEach(Array(otherAgents.prefix(2).enumerated()), id: \.offset) { _, agent in
                agentChip(agent)
            }
            Spacer(minLength: 24)
            let running = store.agents.filter { $0.status == "running" }.count
            if running > 0 {
                BlinkingDot()
            }
            Text("\(running) running")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.leading, 14)
        .padding(.trailing, 18)
    }

    private var claudeSessionChip: some View {
        HStack(spacing: 5) {
            ClaudeMark(color: Color(hex: "cc785c"), active: true)
                .frame(width: 12, height: 12)
            Text("Claude Code")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.82))
            if claudeSessions.count > 1 {
                Text("\(claudeSessions.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: "cc785c"))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color(hex: "cc785c").opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func agentChip(_ agent: AgentStatus) -> some View {
        HStack(spacing: 5) {
            PulseDot(color: Color(hex: agent.color), active: agent.status == "running")
            Text(agent.displayName)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
