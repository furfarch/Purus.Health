import Foundation
import CloudKit

@MainActor
final class CloudKitSharePermissionService {
    static let shared = CloudKitSharePermissionService()

    enum EffectivePermission { case unknown, readOnly, readWrite }

    private let containerIdentifier = AppConfig.CloudKit.containerID
    private var container: CKContainer { CKContainer(identifier: containerIdentifier) }

    // Keep in sync with CloudSyncService.shareZoneName
    private let shareZoneName = AppConfig.CloudKit.shareZoneName
    private var shareZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: shareZoneName, ownerName: CKCurrentUserDefaultName)
    }

    private init() {}

    func permission(for record: MedicalRecord) async -> EffectivePermission {
        guard let shareName = record.cloudShareRecordName, !shareName.isEmpty else {
            return record.isSharingEnabled ? .readWrite : .unknown
        }

        do {
            let db = container.privateCloudDatabase
            let shareID = CKRecord.ID(recordName: shareName, zoneID: shareZoneID)
            let share: CKShare?
            do {
                share = try await db.record(for: shareID) as? CKShare
            } catch let ck as CKError where ck.code == .unknownItem || ck.code == .zoneNotFound {
                // Receiver: the share lives in the owner's zone, reachable only via the shared database.
                share = await fetchReceivedShare(named: shareName)
            }
            switch share?.currentUserParticipant?.permission {
            case .readOnly: return .readOnly
            case .readWrite: return .readWrite
            default: return .unknown
            }
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitSharePermissionService: permission fetch failed for share=\(shareName): \(error)")
            return .unknown
        }
    }

    /// Finds a received CKShare by record name across the shared database zones (nil if not found).
    func fetchReceivedShare(named shareName: String) async -> CKShare? {
        let sharedDB = container.sharedCloudDatabase
        guard let zones = try? await sharedDB.allRecordZones() else { return nil }
        for zone in zones {
            let id = CKRecord.ID(recordName: shareName, zoneID: zone.zoneID)
            if let share = try? await sharedDB.record(for: id) as? CKShare { return share }
        }
        return nil
    }
}
