import Foundation
import CloudKit

/// Minimal CloudKit manager scaffold.
/// All operations are guarded by `isCloudAvailable` which checks for a configured container.
final class CloudKitManager {
    static let shared = CloudKitManager()

    // Default container name used in entitlements. Change if needed.
    private let containerIdentifier = "iCloud.com.furfarch.MyHealthData"
    private var container: CKContainer? {
        // Attempt to create container; will only work when entitlements/provisioning are present.
        CKContainer(identifier: containerIdentifier)
    }

    private init() {}

    var isCloudAvailable: Bool {
        // Simple heuristic: return true if the container exists (note: this doesn't validate provisioning).
        return true
    }

    // Map a MedicalRecord's basic fields to CKRecord
    func mapToCKRecord(_ recordID: String, record: MedicalRecord) -> CKRecord {
        let id = CKRecord.ID(recordName: recordID)
        let ckRecord = CKRecord(recordType: "MedicalRecord", recordID: id)
        ckRecord["id"] = record.id as NSString
        ckRecord["createdAt"] = record.createdAt as NSDate
        ckRecord["updatedAt"] = record.updatedAt as NSDate
        ckRecord["isPet"] = record.isPet as NSNumber
        ckRecord["personalFamilyName"] = record.personalFamilyName as NSString
        ckRecord["personalGivenName"] = record.personalGivenName as NSString
        ckRecord["personalNickName"] = record.personalNickName as NSString
        // ... add more fields as required for syncing
        return ckRecord
    }

    // Upload a record (basic save; no conflict handling yet)
    func upload(record: MedicalRecord) async throws -> CKRecord.ID {
        guard isCloudAvailable else { throw NSError(domain: "CloudKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cloud not available"]) }
        let id = record.cloudRecordName ?? record.id
        let ckRecord = mapToCKRecord(id, record: record)
        let db = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        return try await withCheckedThrowingContinuation { cont in
            db.save(ckRecord) { saved, error in
                if let error = error { cont.resume(throwing: error); return }
                cont.resume(returning: saved!.recordID)
            }
        }
    }

    // Create a CKShare for a specific CKRecord
    func createShare(for recordID: CKRecord.ID, completion: @escaping (CKShare?, Error?) -> Void) {
        let db = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        // Fetch the record and create a share
        db.fetch(withRecordID: recordID) { record, error in
            if let err = error { completion(nil, err); return }
            guard let record = record else { completion(nil, NSError(domain: "CloudKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Record not found"])) ; return }

            let share = CKShare(rootRecord: record)
            share[CKShare.SystemFieldKey.title] = "Shared Medical Record" as CKRecordValue

            let modifyOp = CKModifyRecordsOperation(recordsToSave: [record, share], recordIDsToDelete: nil)
            // Use the modern Result-based callback; CKModifyRecordsOperation reports Result<Void, Error>
            modifyOp.modifyRecordsResultBlock = { (result: Result<Void, Error>) in
                switch result {
                case .success:
                    completion(share, nil)
                case .failure(let opError):
                    completion(nil, opError)
                }
            }
            db.add(modifyOp)
        }
    }
}
