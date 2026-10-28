import SwiftUI

/// Settings for home server mode.
struct HomeServerSettingsView: View {
    @ObservedObject private var sync = HomeServerSyncService.shared

    @State private var isEnabled: Bool = HomeServerSettings.isEnabled
    @State private var urlString: String = HomeServerSettings.urlString
    @State private var isPaired: Bool = HomeServerSettings.isPaired
    @State private var pairedAt: Date? = HomeServerSettings.pairedAt
    @State private var pasteResult: String?
    @State private var showUnpairConfirm = false
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
                .disabled(isConnecting || sync.isSyncing || (!isEnabled && !isPaired))
            } footer: {
                Text("When on, your home server is the main copy of all records and iCloud sync is paused. When off, the app works with iCloud as before.")
            }

            Section("Server") {
                TextField("Server address", text: $urlString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit { HomeServerSettings.urlString = urlString }
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

            Section {
                if isPaired {
                    HStack {
                        Text("Paired")
                        Spacer()
                        if let pairedAt {
                            Text(pairedAt, format: .dateTime.day().month().year())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Remove pairing from this device", role: .destructive) { showUnpairConfirm = true }
                        .disabled(isEnabled)
                } else {
                    Button("Paste pairing code") { pasteCode() }
                    if let url = HomeServerSettings.addDeviceURL {
                        Link("Add this device in Home › Devices", destination: url)
                    }
                }
                if let pasteResult {
                    Text(pasteResult).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Pairing")
            } footer: {
                Text(isPaired
                     ? "See or remove this device in Home › Devices. Turn the home server off before removing the pairing here."
                     : "Add the device in Home › Devices. Then scan the QR code with the Camera app, or copy the code and tap Paste pairing code. The app then switches to the home server by itself.")
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
        }
        .onReceive(NotificationCenter.default.publisher(for: HomeServerPairing.didPair)) { _ in refreshPairing() }
        .alert("Remove pairing?", isPresented: $showUnpairConfirm) {
            Button("Remove", role: .destructive) {
                HomeServerSettings.unpair()
                refreshPairing()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This device can no longer use the home server until it is paired again. To block it on the server too, remove it in Home › Devices.")
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
    }

    private func refreshPairing() {
        isPaired = HomeServerSettings.isPaired
        pairedAt = HomeServerSettings.pairedAt
        urlString = HomeServerSettings.urlString
        if isPaired { pasteResult = nil }
    }

    private func pasteCode() {
        let text = UIPasteboard.general.string ?? ""
        if HomeServerPairing.pair(text: text) {
            pasteResult = nil
            refreshPairing()
            // paired -> switch to the home server right away
            if !isEnabled { Task { await connect() } }
        } else {
            pasteResult = text.isEmpty ? "Nothing to paste. Copy the pairing code first." : "This is not a valid pairing code."
        }
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
