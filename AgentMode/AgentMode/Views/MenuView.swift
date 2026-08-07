import SwiftUI

/// The menu-bar dropdown: live status per section 6 of the brief.
struct MenuView: View {
    @Environment(AgentModeEngine.self) private var engine
    @Environment(\.openSettings) private var openSettings
    @State private var settings = AppSettings.shared

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(headerColor)
                    .frame(width: 8, height: 8)
                Text("Agent Mode: \(settings.agentModeEnabled ? "ON" : "OFF")")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("", isOn: $settings.agentModeEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Text(engine.state.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Divider()

            // Agents
            if engine.agents.isEmpty {
                Text("No agents detected")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(engine.agents) { agent in
                        agentRow(agent)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            Divider()

            // Power section
            VStack(alignment: .leading, spacing: 4) {
                statusLine(
                    label: "Power",
                    value: engine.power.onACPower ? "Connected" : "On battery"
                )
                statusLine(label: "Battery", value: engine.power.batteryText)
                statusLine(label: "Sleep", value: engine.sleepStatusText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            // Controls
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Keep awake even with no agents", isOn: $settings.forceKeepAwake)
                    .font(.system(size: 12))

                Toggle("Lid-closed mode (admin)", isOn: Binding(
                    get: { engine.lidClosedModeEnabled },
                    set: { engine.setLidClosedMode($0) }
                ))
                .font(.system(size: 12))

                HStack {
                    Text("After agents finish")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: $settings.gracePeriod) {
                        ForEach(GracePeriod.allCases) { g in
                            Text(g.label).tag(g)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                if let error = engine.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            HStack {
                Button("Settings…") {
                    // Accessory-policy apps open Settings behind other windows
                    // unless activated first.
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                .font(.system(size: 12))
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 300)
    }

    private var headerColor: Color {
        if engine.isHoldingAwake { return .green }
        if case .grace = engine.state { return .orange }
        if case .batteryHold = engine.state { return .red }
        return .secondary.opacity(0.5)
    }

    private func agentRow(_ agent: AgentProcess) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 11))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(agent.displayName) — Running — \(agent.runtimeText)")
                    .font(.system(size: 12))
                Text("pid \(agent.pid) · \(Int(agent.cpuPercent))% CPU · \(agent.memoryText)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func statusLine(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12))
        }
    }
}
