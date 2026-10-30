import SwiftUI
import CloudKit

struct SettingsView: View {
    @State private var accountStatus: CKAccountStatus?
    @State private var accountStatusError: String?

    private let containerIdentifier = AppConfig.CloudKit.containerID

    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ExportSettingsView()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    NavigationLink {
                        HomeServerSettingsView()
                    } label: {
                        Label("Home Server", systemImage: "server.rack")
                    }
                }

                Section {
                    if HomeServerSettings.isEnabled {
                        Text("iCloud sync and sharing are paused while the home server is on.")
                            .foregroundStyle(.secondary)
                    } else {
                        NavigationLink {
                            CloudRecordSettingsView()
                        } label: {
                            Label("iCloud Sync and Sharing of Records", systemImage: "icloud")
                        }
                    }
                } header: {
                    Text("iCloud")
                }

                Section {

                    HStack {
                        Text("Status")
                        Spacer()
                        Text(accountStatus.map(accountStatusText) ?? "Checking…")
                            .foregroundStyle(.secondary)
                    }

                    if let accountStatusError {
                        Text(accountStatusError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Re-check iCloud Status") {
                        Task { await refreshAccountStatus() }
                    }

                    // Export Share Logs removed for Release per request.
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Settings")
            .task {
                await refreshAccountStatus()
            }
        }
    }

    private func refreshAccountStatus() async {
        accountStatusError = nil
        do {
            let status = try await CKContainer(identifier: containerIdentifier).accountStatus()
            accountStatus = status
        } catch {
            accountStatus = nil
            accountStatusError = "iCloud status check failed: \(error.localizedDescription)"
        }
    }

    private func accountStatusText(_ status: CKAccountStatus) -> String {
        switch status {
        case .available:
            return "Available"
        case .noAccount:
            return "No iCloud account"
        case .restricted:
            return "Restricted"
        case .couldNotDetermine:
            return "Could not determine"
        case .temporarilyUnavailable:
            return "Temporarily unavailable"
        @unknown default:
            return "Unknown"
        }
    }
}

#Preview {
    SettingsView()
}

