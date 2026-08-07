import SwiftUI

struct SettingsView: View {
    @Environment(AgentModeEngine.self) private var engine
    @State private var settings = AppSettings.shared
    @State private var newProcessName = ""

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Smart sleep") {
                Picker("Restore sleep after agents finish", selection: $settings.gracePeriod) {
                    ForEach(GracePeriod.allCases) { g in
                        Text(g.label).tag(g)
                    }
                }
                Picker("Failsafe: never stay awake longer than", selection: $settings.failsafeTimeout) {
                    ForEach(FailsafeTimeout.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
            }

            Section("Battery protection") {
                HStack {
                    Text("Release keep-awake below")
                    Spacer()
                    Stepper(
                        "\(settings.batteryCutoffPercent)%",
                        value: $settings.batteryCutoffPercent,
                        in: 10...80,
                        step: 5
                    )
                }
                Toggle("Require charger to keep Mac awake", isOn: $settings.requireCharger)
                Text("Agent Mode never engages below \(AppSettings.criticalBatteryPercent)% on battery, and never overrides macOS thermal protections.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Monitored processes") {
                Text("Built in: Claude Code, Codex, OpenClaw, Cursor Agent, Aider")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(settings.customProcessNames, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button(role: .destructive) {
                            settings.customProcessNames.removeAll { $0 == name }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Process name contains…", text: $newProcessName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = newProcessName.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        settings.customProcessNames.append(trimmed)
                        newProcessName = ""
                    }
                }
            }

            Section("General") {
                Toggle("Notifications", isOn: $settings.notificationsEnabled)
                // Read the live SMAppService status so the toggle can't drift
                // from changes made in System Settings.
                Toggle("Launch at login", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { on in
                        if LoginItem.set(enabled: on) {
                            settings.launchAtLogin = on
                        }
                    }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 520)
    }
}
