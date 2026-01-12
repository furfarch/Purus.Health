import Foundation
import CloudKit
import SwiftData
import Combine

@MainActor
/// Fetches MedicalRecord records from CloudKit (private database by default).
class CloudKitMedicalRecordFetcher: ObservableObject {
    @Published var records: [CKRecord] = []
    @Published var error: Error?
    @Published var isLoading: Bool = false

    private let container: CKContainer
    private let database: CKDatabase
    private let recordType = "MedicalRecord"
    private var modelContext: ModelContext?

    // Keep in sync with CloudSyncService.shareZoneName
    private let shareZoneName = "MyHealthDataShareZone"
    private var shareZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: shareZoneName, ownerName: CKCurrentUserDefaultName)
    }

    init(containerIdentifier: String = "iCloud.com.furfarch.MyHealthData", modelContext: ModelContext? = nil) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        self.modelContext = modelContext
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func fetchAll() {
        isLoading = true
        error = nil
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)
        operation.zoneID = shareZoneID
        var fetched: [CKRecord] = []
        // Use modern per-record callback to surface per-record errors and collect records.
        operation.recordMatchedBlock = { (recordID, result) in
            switch result {
            case .success(let rec):
                fetched.append(rec)
            case .failure(let err):
                ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: recordMatchedBlock error: \(err)")
            }
        }

        operation.queryResultBlock = { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success:
                    self?.records = fetched
                    if let context = self?.modelContext {
                        ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: performing sync/merge of \(fetched.count) records into local store")
                        self?.importToSwiftData(context: context)
                        ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: sync/merge complete for \(fetched.count) records")
                    }
                case .failure(let err):
                    if let ck = err as? CKError, ck.code == .zoneNotFound {
                        ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: zone not found (\(self?.shareZoneName ?? "")), treating as empty cloud state")
                        self?.records = []
                        return
                    }
                    self?.error = err
                    ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: queryResultBlock error: \(err)")
                }
            }
        }
        database.add(operation)
    }

    /// Async API: fetch all records and import them into local SwiftData; returns number of fetched records.
    func fetchAllAsync() async throws -> Int {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            isLoading = true
            error = nil
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            let op = CKQueryOperation(query: query)
            op.zoneID = shareZoneID
            var fetched: [CKRecord] = []

            op.recordMatchedBlock = { (_, result) in
                switch result {
                case .success(let rec): fetched.append(rec)
                case .failure(let err): ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: recordMatchedBlock error: \(err)")
                }
            }

            op.queryResultBlock = { [weak self] result in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    switch result {
                    case .success:
                        self?.records = fetched
                        if let context = self?.modelContext {
                            ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: (async) performing sync/merge of \(fetched.count) records into local store")
                            self?.importToSwiftData(context: context)
                            ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: (async) sync/merge complete for \(fetched.count) records")
                        }
                        continuation.resume(returning: fetched.count)
                    case .failure(let err):
                        if let ck = err as? CKError, ck.code == .zoneNotFound {
                            ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: (async) zone not found (\(self?.shareZoneName ?? "")), treating as empty cloud state")
                            self?.records = []
                            continuation.resume(returning: 0)
                            return
                        }
                        self?.error = err
                        ShareDebugStore.shared.appendLog("CloudKitMedicalRecordFetcher: (async) queryResultBlock error: \(err)")
                        continuation.resume(throwing: err)
                    }
                }
            }

            database.add(op)
        }
    }

    /// Import fetched CKRecords into the local SwiftData store as MedicalRecord objects.
    func importToSwiftData(context: ModelContext) {
        for ckRecord in records {
            guard let uuid = ckRecord["uuid"] as? String else { continue }

            let cloudUpdatedAt = (ckRecord["updatedAt"] as? Date) ?? Date.distantPast

            let fetchDescriptor = FetchDescriptor<MedicalRecord>(predicate: #Predicate { $0.uuid == uuid })
            let existing = (try? context.fetch(fetchDescriptor))?.first

            // Prevent stale cloud copies from overwriting newer local edits.
            if let existing, existing.updatedAt > cloudUpdatedAt {
                continue
            }

            let record = existing ?? MedicalRecord(uuid: uuid)

            record.createdAt = ckRecord["createdAt"] as? Date ?? record.createdAt
            record.updatedAt = cloudUpdatedAt

            record.personalFamilyName = ckRecord["personalFamilyName"] as? String ?? ""
            record.personalGivenName = ckRecord["personalGivenName"] as? String ?? ""
            record.personalNickName = ckRecord["personalNickName"] as? String ?? ""
            record.personalGender = ckRecord["personalGender"] as? String ?? ""
            record.personalBirthdate = ckRecord["personalBirthdate"] as? Date
            record.personalSocialSecurityNumber = ckRecord["personalSocialSecurityNumber"] as? String ?? ""
            record.personalAddress = ckRecord["personalAddress"] as? String ?? ""
            record.personalHealthInsurance = ckRecord["personalHealthInsurance"] as? String ?? ""
            record.personalHealthInsuranceNumber = ckRecord["personalHealthInsuranceNumber"] as? String ?? ""
            record.personalEmployer = ckRecord["personalEmployer"] as? String ?? ""

            if let boolVal = ckRecord["isPet"] as? Bool {
                record.isPet = boolVal
            } else if let num = ckRecord["isPet"] as? NSNumber {
                record.isPet = num.boolValue
            }

            record.personalName = ckRecord["personalName"] as? String ?? ""
            record.personalAnimalID = ckRecord["personalAnimalID"] as? String ?? ""
            record.ownerName = ckRecord["ownerName"] as? String ?? ""
            record.ownerPhone = ckRecord["ownerPhone"] as? String ?? ""
            record.ownerEmail = ckRecord["ownerEmail"] as? String ?? ""
            record.emergencyName = ckRecord["emergencyName"] as? String ?? ""
            record.emergencyNumber = ckRecord["emergencyNumber"] as? String ?? ""
            record.emergencyEmail = ckRecord["emergencyEmail"] as? String ?? ""

            record.isCloudEnabled = true
            record.cloudRecordName = ckRecord.recordID.recordName

            if existing == nil {
                context.insert(record)
            }
        }

        do {
            try context.save()
        } catch {
            print("Failed to save CloudKit import: \(error)")
        }
    }
}
