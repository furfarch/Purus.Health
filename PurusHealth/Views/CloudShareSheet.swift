import SwiftUI
import CloudKit
import SwiftData

import UIKit

private enum SharePermissionChoice: Hashable { case readWrite, readOnly }

struct CloudShareSheet: View {
    let record: MedicalRecord

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var isBusy = false
    @State private var errorMessage: String?

    @State private var showShareSheet = false
    @State private var shareController: UICloudSharingController?
    @State private var selectedPermissionChoice: SharePermissionChoice = .readOnly

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Share this record using iCloud. You can invite others and manage permissions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section("Error") { Text(errorMessage).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task { await presentShareSheet_iOS() }
                    } label: {
                        if isBusy { ProgressView() } else { Text("Share Record") }
                    }
                    Picker("Permission", selection: $selectedPermissionChoice) {
                        Text("Read/Write").tag(SharePermissionChoice.readWrite)
                        Text("Read Only").tag(SharePermissionChoice.readOnly)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Sharing Permission")
                    Text("As the owner, you can invite people and change their permissions (read-only or read-write).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .background(
                    ShareSheetPresenter(controller: $shareController, isPresented: $showShareSheet)
                )
            }
            .navigationTitle("Share Record")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    // MARK: - iOS flow
    @MainActor
    private func presentShareSheet_iOS() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let permissionOptions: UICloudSharingController.PermissionOptions = (selectedPermissionChoice == .readWrite) ? .allowReadWrite : .allowReadOnly
            let controller = try await CloudSyncService.shared.makeCloudSharingController(for: record, preferredPermissions: permissionOptions) { result in
                DispatchQueue.main.async {
                    self.showShareSheet = false
                    switch result {
                    case .success(let url):
                        self.errorMessage = nil
                        // Sharing is on only once a share was actually saved (nil url = stopped sharing).
                        record.isSharingEnabled = (url != nil)
                        record.updatedAt = Date()
                        try? modelContext.save()
                        Task { @MainActor in
                            await CloudKitShareParticipantsService.shared.refreshParticipantsSummary(for: record)
                        }
                    case .failure(let err):
                        self.errorMessage = err.localizedDescription
                    }
                }
            }
            shareController = controller
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    struct ShareSheetPresenter: UIViewControllerRepresentable {
        @Binding var controller: UICloudSharingController?
        @Binding var isPresented: Bool
        func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
        func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
            guard isPresented, let controller else { return }
            if uiViewController.presentedViewController == nil {
                uiViewController.present(controller, animated: true) { isPresented = false }
            }
        }
    }

}
