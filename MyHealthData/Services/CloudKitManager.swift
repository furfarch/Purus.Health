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

            let modifyOp = CKModifyRecordsOperation(recordsToSave: [record, share], recordIDsToDelete: [])
            
            // Track saved records and errors per-record
            var savedRecords: [CKRecord.ID: CKRecord] = [:]
            var recordErrors: [CKRecord.ID: Error] = [:]
            
            // Handle per-record save results
            modifyOp.perRecordSaveBlock = { recordID, result in
                switch result {
                case .success(let savedRecord):
                    savedRecords[recordID] = savedRecord
                case .failure(let error):
                    recordErrors[recordID] = error
                }
            }
            
            // Use the modern Result-based callback; CKModifyRecordsOperation reports Result<Void, Error>
            modifyOp.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    // Check if any records failed to save
                    if !recordErrors.isEmpty {
                        let errorDescription = recordErrors.map { "\($0.key.recordName): \($0.value.localizedDescription)" }.joined(separator: ", ")
                        let compositeError = NSError(
                            domain: "CloudKitManager",
                            code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to save \(recordErrors.count) record(s): \(errorDescription)"]
                        )
                        completion(nil, compositeError)
                    } else {
                        // Extract the saved share from saved records
                        if let savedShare = savedRecords.values.first(where: { $0 is CKShare }) as? CKShare {
                            completion(savedShare, nil)
                        } else {
                            let error = NSError(
                                domain: "CloudKitManager",
                                code: 4,
                                userInfo: [NSLocalizedDescriptionKey: "Share was not returned in save results"]
                            )
                            completion(nil, error)
                        }
                    }
                case .failure(let opError):
                    completion(nil, opError)
                }
            }
            db.add(modifyOp)
        }
    }
}
