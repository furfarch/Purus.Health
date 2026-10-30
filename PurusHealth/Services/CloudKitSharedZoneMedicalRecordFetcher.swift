import Foundation
import CloudKit
import SwiftData

/// Fetches MedicalRecord records from the CloudKit Shared database by iterating record zones.
///
/// Why this exists
/// Shared records live in *shared record zones* (often one zone per share). A plain query against
/// `sharedCloudDatabase` without supplying `zoneID` can miss results or behave inconsistently.
@MainActor
final class CloudKitSharedZoneMedicalRecordFetcher {
    private let container: CKContainer
    private let database: CKDatabase
    private var modelContext: ModelContext?

    // Keep in sync with the owner's record type.
    private let recordType = AppConfig.CloudKit.recordType

    init(containerIdentifier: String, modelContext: ModelContext? = nil) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.sharedCloudDatabase
        self.modelContext = modelContext
    }

    convenience init(modelContext: ModelContext? = nil) {
        self.init(containerIdentifier: AppConfig.CloudKit.containerID, modelContext: modelContext)
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    /// Fetch shared records across all shared record zones and merge them into SwiftData.
    /// Returns the number of fetched records.
    func fetchAllSharedAcrossZonesAsync() async throws -> Int {
        // Home server mode: iCloud sync is paused
        if HomeServerSettings.isEnabled { return 0 }
        let zones = try await fetchAllRecordZones()

        var totalFetched = 0
        var returnedUUIDs = Set<String>()
        var complete = true
        for zone in zones {
            // One failing zone must not stop the others.
            do {
                let fetched = try await fetchAllShared(in: zone.zoneID)
                totalFetched += fetched.count
                returnedUUIDs.formUnion(fetched.compactMap { $0["uuid"] as? String })
            } catch {
                complete = false
                ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: zone \(zone.zoneID.zoneName) failed: \(error)")
            }
        }
        // Only a complete fetch proves a record is no longer shared.
        if complete {
            await removeUnsharedReceivedRecords(keeping: returnedUUIDs)
        }
        return totalFetched
    }

    /// Deletes local received records whose share is gone. A record counts as received when it has a share name
    /// but no root in this user's private share zone (owners always have one).
    private func removeUnsharedReceivedRecords(keeping returned: Set<String>) async {
        guard let context = modelContext else { return }
        let candidates = ((try? context.fetch(FetchDescriptor<MedicalRecord>())) ?? []).filter {
            $0.cloudShareRecordName != nil && !$0.isMarkedForDeletion && !returned.contains($0.uuid)
        }
        guard !candidates.isEmpty else { return }

        let zoneID = CKRecordZone.ID(zoneName: AppConfig.CloudKit.shareZoneName, ownerName: CKCurrentUserDefaultName)
        let ids = candidates.map { CKRecord.ID(recordName: $0.cloudRecordName ?? $0.uuid, zoneID: zoneID) }
        var notOwned = Set<CKRecord.ID>()
        do {
            let results = try await container.privateCloudDatabase.records(for: ids)
            for (id, result) in results {
                if case .failure(let err) = result, (err as? CKError)?.code == .unknownItem { notOwned.insert(id) }
            }
        } catch let ck as CKError where ck.code == .zoneNotFound {
            notOwned = Set(ids)
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: ownership check failed, skipping cleanup: \(error)")
            return
        }
        guard !notOwned.isEmpty else { return }

        for (record, id) in zip(candidates, ids) where notOwned.contains(id) {
            ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: removing no-longer-shared record uuid=\(record.uuid)")
            context.delete(record)
        }
        do {
            try context.save()
            NotificationCenter.default.post(name: NotificationNames.didImportRecords, object: nil)
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: failed saving cleanup: \(error)")
        }
    }

    // MARK: - Zones

    private func fetchAllRecordZones() async throws -> [CKRecordZone] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CKRecordZone], Error>) in
            database.fetchAllRecordZones { zones, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: zones ?? [])
            }
        }
    }

    // MARK: - Query

    private func fetchAllShared(in zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let op = CKQueryOperation(query: query)
        op.zoneID = zoneID

        var fetched: [CKRecord] = []
        op.recordMatchedBlock = { _, result in
            if case .success(let rec) = result { fetched.append(rec) }
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CKRecord], Error>) in
            op.queryResultBlock = { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        guard let self else { cont.resume(returning: []); return }
                        self.importToSwiftData(records: fetched)
                        cont.resume(returning: fetched)
                    case .failure(let err):
                        cont.resume(throwing: err)
                    }
                }
            }
            database.add(op)
        }
    }

    // MARK: - Import

    private func importToSwiftData(records: [CKRecord]) {
        guard let context = modelContext else {
            ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: no modelContext set; skipping import")
            return
        }

        for ckRecord in records {
            // Skip re-importing records that were locally deleted by user (suppression list)
            if let uuid = ckRecord["uuid"] as? String, SharedImportSuppression.isSuppressed(uuid) {
                ShareDebugStore.shared.appendLog("SharedZoneFetcher: suppressed re-import for uuid=\(uuid)")
                continue
            }

            guard let uuid = ckRecord["uuid"] as? String else { continue }

            // Owner deleted the record: remove the received copy.
            if let isDeleted = ckRecord["isDeleted"] as? NSNumber, isDeleted.boolValue {
                let tombstoned = FetchDescriptor<MedicalRecord>(predicate: #Predicate { $0.uuid == uuid })
                if let existing = (try? context.fetch(tombstoned))?.first {
                    ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: deleting from tombstone uuid=\(uuid)")
                    context.delete(existing)
                    SharedImportSuppression.clear(uuid)
                }
                continue
            }

            let cloudUpdatedAt = (ckRecord["updatedAt"] as? Date) ?? Date.distantPast

            let fetchDescriptor = FetchDescriptor<MedicalRecord>(predicate: #Predicate { $0.uuid == uuid })
            let existing = (try? context.fetch(fetchDescriptor))?.first

            if let existing, existing.updatedAt > cloudUpdatedAt {
                ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: skipping stale cloud record uuid=\(uuid) (local=\(existing.updatedAt), cloud=\(cloudUpdatedAt))")
                continue
            }

            let record = existing ?? MedicalRecord(uuid: uuid)
            
            if existing != nil {
                ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: updating existing record uuid=\(uuid)")
            } else {
                ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: creating new record uuid=\(uuid)")
            }

            CloudKitMedicalRecordFetcher.apply(ckRecord: ckRecord, to: record, context: context)

            // Shared records should always be marked as shared and cloud-enabled
            // since they exist in CloudKit (even if user hasn't enabled global cloud sync).
            record.isCloudEnabled = true
            record.cloudRecordName = ckRecord.recordID.recordName

            if let shareRef = ckRecord.share {
                record.cloudShareRecordName = shareRef.recordID.recordName
            }

            if existing == nil {
                context.insert(record)
            }
        }

        // Process pending changes before saving to ensure all modifications are tracked
        context.processPendingChanges()

        do {
            try context.save()
            ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: successfully saved \(records.count) record(s)")
            
            // Post notification to trigger UI refresh (ensure on MainActor for thread safety)
            Task { @MainActor in
                NotificationCenter.default.post(name: NotificationNames.didImportRecords, object: nil)
            }
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitSharedZoneMedicalRecordFetcher: failed saving import: \(error)")
        }
    }
}
