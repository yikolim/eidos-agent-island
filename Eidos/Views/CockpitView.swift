import SwiftUI

struct CockpitView: View {
    @Environment(AgentStore.self) private var store
    @State private var tick = false
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ACTIVE AGENTS")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(0.8)
                Spacer()
                Button(action: { store.islandState = .mini }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .frame(width: 18, height: 18)
                .background(.white.opacity(0.07))
                .clipShape(Circle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(store.agents) { agent in
                        agentRow(agent)
                    }
                }
                .padding(.horizontal, 10)
            }

            Divider().background(.white.opacity(0.07)).padding(.horizontal, 16).padding(.vertical, 8)

            HStack(spacing: 6) {
                quickAction("pause all", icon: "pause.fill") { }
                quickAction("approvals", icon: "bell") { }
                quickAction("settings", icon: "gear") { }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
        .onReceive(timer) { _ in tick.toggle() }
    }

    func agentRow(_ agent: AgentStatus) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(hex: agent.color).opacity(0.15))
                .frame(width: 30, height: 30)
                .overlay {
                    if ClaudeMark.matches(agent.agentID) {
                        ClaudeMark(color: Color(hex: agent.color), active: agent.status == "running")
                            .frame(width: 17, height: 17)
                    } else {
                        Image(systemName: agentIcon(agent.agentID))
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: agent.color))
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.task)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                Text("\(agent.displayName) · \(agent.elapsed)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.07)).frame(height: 2)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: agent.color))
                            .frame(width: geo.size.width * agent.progress, height: 2)
                            .animation(.easeInOut(duration: 0.8), value: agent.progress)
                    }
                }
                .frame(height: 2)
                .padding(.top, 3)
            }

            statusBadge(agent.status)
        }
        .padding(10)
        .background(.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    func statusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = switch status {
        case "running": ("running", Color(hex: "4ade80"))
        case "paused":  ("paused",  Color(hex: "faad14"))
        case "done":    ("done",    .white.opacity(0.3))
        default:        ("error",   Color(hex: "f87171"))
        }
        return Text(label)
            .font(.system(size: 10))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    func quickAction(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 11))
            }
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    func agentIcon(_ id: String) -> String {
        if id == "codex" { return "cpu" }
        if ClaudeMark.matches(id) { return "bolt.circle" }
        return "terminal"
    }
}
