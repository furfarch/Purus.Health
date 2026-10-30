import Foundation
import CloudKit

/// Fetches participants (including pending) for a CKShare and formats them for display.
@MainActor
final class CloudKitShareParticipantsService {
    static let shared = CloudKitShareParticipantsService()

    private let containerIdentifier = AppConfig.CloudKit.containerID
    private var container: CKContainer { CKContainer(identifier: containerIdentifier) }

    // Keep in sync with CloudSyncService.shareZoneName
    private let shareZoneName = AppConfig.CloudKit.shareZoneName
    private var shareZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: shareZoneName, ownerName: CKCurrentUserDefaultName)
    }

    private init() {}

    func refreshParticipantsSummary(for record: MedicalRecord) async {
        guard let shareRecordName = record.cloudShareRecordName, !shareRecordName.isEmpty else {
            record.shareParticipantsSummary = ""
            return
        }

        do {
            let db = container.privateCloudDatabase
            let shareID = CKRecord.ID(recordName: shareRecordName, zoneID: shareZoneID)
            let fetched: CKRecord?
            do {
                fetched = try await db.record(for: shareID)
            } catch let ck as CKError where ck.code == .unknownItem || ck.code == .zoneNotFound {
                // Not owned here: a received share is only visible in the shared database.
                fetched = await CloudKitSharePermissionService.shared.fetchReceivedShare(named: shareRecordName)
            }
            guard let share = fetched as? CKShare else {
                record.shareParticipantsSummary = ""
                return
            }

            record.shareParticipantsSummary = Self.formatParticipants(share.participants)
        } catch {
            // Best effort: keep existing value, but log.
            ShareDebugStore.shared.appendLog("CloudKitShareParticipantsService: refresh failed share=\(shareRecordName) zone=\(shareZoneName) error=\(error)")
        }
    }

    static func formatParticipants(_ participants: [CKShare.Participant]) -> String {
        let lines: [String] = participants.map { p in
            let nameOrEmail: String = {
                if let name = p.userIdentity.nameComponents?.formatted(.name(style: .medium)), !name.isEmpty { return name }
                if let email = p.userIdentity.lookupInfo?.emailAddress, !email.isEmpty { return email }
                if let phone = p.userIdentity.lookupInfo?.phoneNumber, !phone.isEmpty { return phone }
                if let recordName = p.userIdentity.userRecordID?.recordName { return recordName }
                return "Unknown"
            }()

            let status: String = {
                switch p.acceptanceStatus {
                case .unknown: return "unknown"
                case .pending: return "pending"
                case .accepted: return "accepted"
                case .removed: return "removed"
                @unknown default: return "unknown"
                }
            }()

            let permission: String = {
                switch p.permission {
                case .unknown: return "unknown"
                case .none: return "none"
                case .readOnly: return "read"
                case .readWrite: return "write"
                @unknown default: return "unknown"
                }
            }()

            return "\(nameOrEmail) (\(status), \(permission))"
        }

        return lines.isEmpty ? "Only you" : lines.joined(separator: ", ")
    }
}
