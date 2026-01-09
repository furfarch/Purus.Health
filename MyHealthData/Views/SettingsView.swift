import SwiftUI

struct SettingsView: View {
    @AppStorage("cloudEnabled") private var cloudEnabled: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Sync") {
                    Toggle("Enable iCloud Sync (requires iCloud + provisioning)", isOn: $cloudEnabled)

                    if cloudEnabled {
                        Text("iCloud Sync is enabled (UI only). The app is currently running with a local-only database; CloudKit sync will be re-enabled after schema stabilization.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("iCloud Sync is off.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Sharing") {
                    Text("Record sharing requires CloudKit sync and will be enabled later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Diagnostics") {
                    Text("If you see CHHapticPattern / RTIInputSystemClient messages in the Simulator console, those are iOS/Simulator system logs and can be ignored. They are not app errors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
