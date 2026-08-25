import SwiftUI

/// The menu-bar dropdown: live status per section 6 of the brief.
struct MenuView: View {
    @Environment(AgentModeEngine.self) private var engine
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

            // Agents, grouped per app and split by activity
            let working = engine.groups.filter(\.isWorking)
            let idle = engine.groups.filter { !$0.isWorking }

            if engine.agents.isEmpty {
                Text("No agents detected")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if !working.isEmpty {
                        sectionHeader("RUNNING NOW", color: .green)
                        ForEach(working) { group in
                            groupRow(group)
                        }
                    }
                    if !idle.isEmpty {
                        sectionHeader("IDLE — POSSIBLY UNFINISHED", color: .orange)
                            .padding(.top, working.isEmpty ? 0 : 6)
                        ForEach(idle) { group in
                            groupRow(group)
                        }
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

                Toggle("Sleep when agents finish (on battery)", isOn: $settings.activeSleepWhenIdle)
                    .font(.system(size: 12))

                Toggle("Keep screen on while agents run", isOn: $settings.keepDisplayAwake)
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
                // openSettings is macOS 15+; SettingsLink is the 14.0 API.
                // Accessory-policy apps open Settings behind other windows
                // unless activated, so activate alongside the link's action.
                SettingsLink {
                    Text("Settings…")
                        .font(.system(size: 12))
                }
                .simultaneousGesture(TapGesture().onEnded {
                    NSApp.activate(ignoringOtherApps: true)
                })
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

    private func sectionHeader(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
        }
    }

    private func groupRow(_ group: AgentGroup) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 11))
                .foregroundStyle(group.isWorking ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(groupTitle(group))
                    .font(.system(size: 12))
                Text(groupDetail(group))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func groupTitle(_ group: AgentGroup) -> String {
        let status = group.isWorking
            ? "Running — \(group.runtimeText)"
            : "Idle for \(group.idleForText)"
        return "\(group.name) — \(status)"
    }

    private func groupDetail(_ group: AgentGroup) -> String {
        let count = group.processes.count
        let procs = count == 1 ? "1 process" : "\(count) processes"
        return "\(procs) · \(Int(group.totalCPU))% CPU · \(group.memoryText)"
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
