//
//  ContentView.swift
//  Purus Health
//
//  Created by Chris Furfari on 05.01.2026.
//

import SwiftUI
import SwiftData
import CloudKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    // Show alert when a share is accepted and imported
    @State private var showShareAcceptedAlert: Bool = false
    @State private var importedName: String = ""

    // Show alert when share acceptance fails
    @State private var showShareErrorAlert: Bool = false
    @State private var shareErrorMessage: String = ""

    // Result of a home server pairing link: paired -> home server is switched on right away
    @State private var pairingTitle: String?
    @State private var pairingMessage: String = ""

    // A pairing link waits for Face ID, then the user confirms the server
    @ObservedObject private var appLock = AppLock.shared
    @State private var pairHost: String?

    // iCloud shares are not accepted in home server mode (they would be sent to the server)
    @State private var showShareBlockedAlert = false

    var body: some View {
        RecordListView()
            .onReceive(NotificationCenter.default.publisher(for: HomeServerPairing.didPair)) { notif in
                let ok = (notif.userInfo?["ok"] as? Bool) ?? false
                guard ok else {
                    pairingMessage = "The pairing code is not valid. Add the device again in Home › Devices."
                    pairingTitle = "Pairing failed"
                    return
                }
                if HomeServerSettings.isEnabled {
                    pairingMessage = "This device uses the home server with the new pairing."
                    pairingTitle = "Device paired"
                    return
                }
                Task { @MainActor in
                    do {
                        try await HomeServerSyncService.shared.enable()
                        pairingMessage = "The home server is now the main copy. While the home server is on, the app shows only the home server data and iCloud sync is paused. When you turn the home server off, only records that had iCloud sync on are loaded again from iCloud. A backup of the previous data on this device is in the emergency copy folder."
                        pairingTitle = "Home server on"
                    } catch {
                        pairingMessage = "The device is paired, but switching to the home server failed: \(error.localizedDescription) Try again in Settings › Home Server."
                        pairingTitle = "Device paired"
                    }
                }
            }
            .alert(pairingTitle ?? "",
                   isPresented: Binding(get: { pairingTitle != nil }, set: { if !$0 { pairingTitle = nil } })) {
                Button("OK", role: .cancel) { pairingTitle = nil }
            } message: {
                Text(pairingMessage)
            }
            .onReceive(NotificationCenter.default.publisher(for: HomeServerPairing.linkReceived)) { _ in offerPendingPairing() }
            .onChange(of: appLock.locked) { _, _ in offerPendingPairing() }
            .alert("Pair with \(pairHost ?? "")?",
                   isPresented: Binding(get: { pairHost != nil }, set: { if !$0 { pairHost = nil } })) {
                Button("Pair") {
                    pairHost = nil
                    // let this alert close before the result alert opens
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        HomeServerPairing.confirmPending()
                    }
                }
                Button("Cancel", role: .cancel) {
                    pairHost = nil
                    HomeServerPairing.cancelPending()
                }
            } message: {
                Text("This device will use this home server with the new pairing code.")
            }
            .alert("iCloud share not accepted", isPresented: $showShareBlockedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Turn off home server mode to accept iCloud shares.")
            }
            .onOpenURL { url in
                // Home server pairing link (QR code from purus.HEALTH web) - not a share
                if HomeServerPairing.handle(url: url) { return }
                if refuseShareInHomeServerMode() { return }
                // Accept CloudKit share links and import shared records.
                Task { @MainActor in
                    await CloudKitShareAcceptanceService.shared.acceptShare(from: url, modelContext: modelContext)
                }
            }
            .task {
                // Check for pending share URL on first appearance
                await checkPendingShare()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // Check for pending share URL when app becomes active
                if newPhase == .active {
                    Task { @MainActor in
                        await checkPendingShare()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NotificationNames.didAcceptShare)) { notif in
                // Show brief alert with the imported record name(s) and ensure shared-zone fetch ran
                if let userInfo = notif.userInfo, let names = userInfo["names"] as? [String], let first = names.first {
                    importedName = first
                } else {
                    importedName = "record"
                }
                showShareAcceptedAlert = true

                // Force model context to refresh
                modelContext.processPendingChanges()

                // Ensure shared-zone fetch runs and imports any related records
                Task { @MainActor in
                    let sharedFetcher = CloudKitSharedZoneMedicalRecordFetcher(containerIdentifier: AppConfig.CloudKit.containerID, modelContext: modelContext)
                    do {
                        _ = try await sharedFetcher.fetchAllSharedAcrossZonesAsync()
                        ShareDebugStore.shared.appendLog("ContentView: triggered shared-zone fetch after accept")
                        
                        // Force refresh after fetch completes
                        modelContext.processPendingChanges()
                        
                        // Post notification to ensure UI refreshes
                        NotificationCenter.default.post(name: NotificationNames.didImportRecords, object: nil)
                    } catch {
                        ShareDebugStore.shared.appendLog("ContentView: shared-zone fetch after accept failed: \(error)")
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NotificationNames.didChangeSharedRecords)) { _ in
                // Another component requested a UI refresh for shared records - perform a shared-zone fetch
                // (not in home server mode: shared records would be sent to the server)
                if HomeServerSettings.isEnabled { return }
                Task { @MainActor in
                    let sharedFetcher = CloudKitSharedZoneMedicalRecordFetcher(containerIdentifier: AppConfig.CloudKit.containerID, modelContext: modelContext)
                    do {
                        _ = try await sharedFetcher.fetchAllSharedAcrossZonesAsync()
                        ShareDebugStore.shared.appendLog("ContentView: triggered shared-zone fetch for DidChangeSharedRecords")
                        
                        // Force refresh after fetch completes
                        modelContext.processPendingChanges()
                    } catch {
                        ShareDebugStore.shared.appendLog("ContentView: DidChangeSharedRecords fetch failed: \(error)")
                    }
                }
            }
            .alert("Imported", isPresented: $showShareAcceptedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(importedName) imported")
            }
            .onReceive(NotificationCenter.default.publisher(for: NotificationNames.shareAcceptanceFailed)) { notif in
                // Show error alert when share acceptance fails
                if let userInfo = notif.userInfo, let errorMsg = userInfo["error"] as? String {
                    shareErrorMessage = errorMsg
                } else {
                    shareErrorMessage = "An unknown error occurred while accepting the share."
                }
                showShareErrorAlert = true
            }
            .alert("Share Failed", isPresented: $showShareErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(shareErrorMessage)
            }
            .onReceive(NotificationCenter.default.publisher(for: NotificationNames.pendingShareReceived)) { notif in
                // Process share immediately when received from SceneDelegate/AppDelegate
                // This handles the case where onOpenURL doesn't fire due to custom SceneDelegate
                guard let userInfo = notif.userInfo else { return }
                if refuseShareInHomeServerMode() { return }

                // Prefer metadata (more efficient - skips URL fetch)
                if let metadata = userInfo["metadata"] as? CKShare.Metadata {
                    ShareDebugStore.shared.appendLog("ContentView: received pendingShareReceived with metadata")
                    Task { @MainActor in
                        await CloudKitShareAcceptanceService.shared.acceptShare(from: metadata, modelContext: modelContext)
                    }
                    return
                }

                // Fall back to URL
                if let url = userInfo["url"] as? URL {
                    ShareDebugStore.shared.appendLog("ContentView: received pendingShareReceived notification for URL: \(url)")
                    Task { @MainActor in
                        await CloudKitShareAcceptanceService.shared.acceptShare(from: url, modelContext: modelContext)
                    }
                }
            }
    }
    
    /// Home server mode: drop the pending share and tell the user why.
    private func refuseShareInHomeServerMode() -> Bool {
        guard HomeServerSettings.isEnabled else { return false }
        #if canImport(UIKit)
        _ = PendingShareStore.shared.consumeMetadata()
        _ = PendingShareStore.shared.consumeURL()
        #endif
        showShareBlockedAlert = true
        return true
    }

    /// Shows the pairing confirmation once the app is unlocked.
    private func offerPendingPairing() {
        guard !appLock.locked, pairHost == nil, let host = HomeServerPairing.pendingHost else { return }
        pairHost = host
    }

    @MainActor
    private func checkPendingShare() async {
        #if canImport(UIKit)
        if PendingShareStore.shared.pendingMetadata != nil || PendingShareStore.shared.pendingURL != nil,
           refuseShareInHomeServerMode() { return }
        // Check for pending share metadata first (more efficient)
        if let metadata = PendingShareStore.shared.consumeMetadata() {
            ShareDebugStore.shared.appendLog("ContentView: processing pending share metadata from AppDelegate")
            await CloudKitShareAcceptanceService.shared.acceptShare(from: metadata, modelContext: modelContext)
            return
        }

        // Fall back to pending URL
        if let pendingURL = PendingShareStore.shared.consumeURL() {
            ShareDebugStore.shared.appendLog("ContentView: processing pending share URL from AppDelegate")
            await CloudKitShareAcceptanceService.shared.acceptShare(from: pendingURL, modelContext: modelContext)
        }
        #endif
    }
}

#Preview {
    ContentView()
        .modelContainer(for: MedicalRecord.self, inMemory: true)
}
