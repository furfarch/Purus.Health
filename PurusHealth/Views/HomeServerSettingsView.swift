import SwiftUI

/// Settings for home server mode.
struct HomeServerSettingsView: View {
    @ObservedObject private var sync = HomeServerSyncService.shared

    @State private var isEnabled: Bool = HomeServerSettings.isEnabled
    @State private var urlString: String = HomeServerSettings.urlString
    @State private var appKey: String = HomeServerSettings.appKey
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var isConnecting = false
    @State private var showReplaceConfirm = false
    @State private var showTurnOffConfirm = false
    @State private var errorMessage: String?
    @State private var copyFolder: String = ""

    var body: some View {
        Form {
            Section {
                Toggle("Use home server", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        if newValue { showReplaceConfirm = true } else { showTurnOffConfirm = true }
                    }
                ))
                .disabled(isConnecting || sync.isSyncing)
            } footer: {
                Text("When on, your home server is the main copy of all records and iCloud sync is paused. When off, the app works with iCloud as before.")
            }

            Section("Server") {
                TextField("Server address", text: $urlString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit { HomeServerSettings.urlString = urlString }
                SecureField("App key (for access from outside home)", text: $appKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { HomeServerSettings.appKey = appKey }
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("Test connection")
                        if isTesting { Spacer(); ProgressView() }
                    }
                }
                .disabled(isTesting)
                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(testResult == "Connected" ? .green : .red)
                }
            }

            if isEnabled {
                Section("Sync") {
                    HStack {
                        Text("Last sync")
                        Spacer()
                        if sync.isSyncing {
                            ProgressView()
                        } else if let last = sync.lastSync {
                            Text(last, format: .dateTime.day().month().hour().minute())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Never").foregroundStyle(.secondary)
                        }
                    }
                    if let err = sync.lastError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    Button("Sync now") {
                        Task { await sync.sync() }
                    }
                    .disabled(sync.isSyncing)
                }
            }

            Section {
                HStack {
                    Text("Folder")
                    Spacer()
                    Text(copyFolder).foregroundStyle(.secondary)
                }
                if let last = EmergencyCopyService.lastWrite {
                    HStack {
                        Text("Last written")
                        Spacer()
                        Text(last, format: .dateTime.day().month().hour().minute())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Emergency copy")
            } footer: {
                Text("In home server mode, a PDF per record and a full backup file are written to this folder after every sync, so the data is available even when the server is not.")
            }

            if isConnecting {
                Section {
                    HStack {
                        ProgressView()
                        Text("Backing up and loading data from the home server…")
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Home Server")
        .task { copyFolder = await EmergencyCopyService.folderDescription() }
        .onDisappear {
            HomeServerSettings.urlString = urlString
            HomeServerSettings.appKey = appKey
        }
        .alert("Replace data on this device?", isPresented: $showReplaceConfirm) {
            Button("Replace with server data", role: .destructive) {
                Task { await connect() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All records on this device are replaced with the data from the home server. A backup of the current data is saved to the emergency copy folder first. Nothing from this device is sent to the server.")
        }
        .alert("Turn off home server?", isPresented: $showTurnOffConfirm) {
            Button("Turn off", role: .destructive) {
                sync.disable()
                isEnabled = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The records stay on this device and are no longer synced with the home server. iCloud sync works again for records where it is switched on.")
        }
        .alert("Home server", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func saveFields() {
        HomeServerSettings.urlString = urlString
        HomeServerSettings.appKey = appKey
    }

    private func testConnection() async {
        saveFields()
        isTesting = true
        defer { isTesting = false }
        if let err = await sync.testConnection() {
            testResult = err
        } else {
            testResult = "Connected"
        }
    }

    private func connect() async {
        saveFields()
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await sync.enable()
            isEnabled = true
        } catch {
            isEnabled = false
            errorMessage = error.localizedDescription
        }
    }
}
