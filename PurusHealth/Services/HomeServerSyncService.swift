import Foundation
import SwiftData
import Combine

/// Syncs all records with the home server (Health API, purus_health database).
///
/// How it works:
/// - The last data received from the server is kept as a snapshot.
/// - On each sync, local data is compared with the snapshot: new / changed / deleted entries are sent.
/// - Then everything is fetched from the server and applied locally. The server is the main copy.
/// - First connect: a backup of the phone data is written to iCloud Drive, then local data is
///   replaced with the server data (nothing from the phone is sent).
@MainActor
final class HomeServerSyncService: ObservableObject {
    static let shared = HomeServerSyncService()

    enum SyncError: LocalizedError {
        case noURL
        case http(Int)
        case badResponse(String)
        case backupFailed(String)

        var errorDescription: String? {
            switch self {
            case .noURL: return "No home server address set."
            case .http(401):
                return HomeServerSettings.isPaired
                    ? "This device is not paired any more (removed in Home › Devices). Pair it again."
                    : "This device is not paired yet. Add it in purus.HEALTH web › Settings › Devices."
            case .http(let code): return "Home server answered with HTTP \(code)."
            case .badResponse(let s): return s
            case .backupFailed(let s): return "Backup before replacing failed: \(s)"
            }
        }
    }

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSync: Date? = HomeServerSettings.lastSync
    @Published private(set) var lastError: String? = HomeServerSettings.lastError

    private var container: ModelContainer?
    private var saveObserver: AnyCancellable?
    private var pendingSyncTask: Task<Void, Never>?
    private var syncAgain = false
    /// Saves made by the sync itself must not start another sync.
    private var ignoreSavesUntil = Date.distantPast

    private let profileTable = "profiles"
    private let personalTable = "personal_information"
    private let petTable = "pet_information"

    private init() {}

    // MARK: - Setup

    func configure(container: ModelContainer) {
        self.container = container
        saveObserver = NotificationCenter.default.publisher(for: ModelContext.didSave)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, HomeServerSettings.isEnabled, !self.isSyncing,
                      Date() > self.ignoreSavesUntil else { return }
                self.scheduleSync()
            }
    }

    /// Debounced sync after local saves.
    func scheduleSync(delay: Double = 2.0) {
        pendingSyncTask?.cancel()
        pendingSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    // MARK: - Public actions

    /// Checks that the server answers.
    func testConnection() async -> String? {
        do {
            _ = try await post(["action": "ping"])
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Turns home server mode on: backup phone data, then replace it with the server data.
    func enable() async throws {
        guard let context = container?.mainContext else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let server = try await pullAll()
            do {
                _ = try await EmergencyCopyService.writeBackup(data: fullBackupJSON(context: context),
                                                               prefix: "Phone backup before home server")
            } catch {
                throw SyncError.backupFailed(error.localizedDescription)
            }
            var state = SyncState()
            apply(server: server, localBefore: nil, state: &state, context: context)
            ownSave(context)
            state.snapshot = server
            saveState(state)
            HomeServerSettings.isEnabled = true
            finish(error: nil)
            await writeEmergencyCopy(context: context)
        } catch {
            finish(error: error.localizedDescription)
            throw error
        }
    }

    func disable() {
        pendingSyncTask?.cancel()
        HomeServerSettings.isEnabled = false
        clearState()
    }

    /// Normal sync: send local changes, then fetch and apply server data.
    func sync() async {
        guard HomeServerSettings.isEnabled, let context = container?.mainContext else { return }
        if isSyncing { syncAgain = true; return }
        isSyncing = true
        defer {
            isSyncing = false
            if syncAgain { syncAgain = false; scheduleSync(delay: 0.5) }
        }

        do {
            var state = loadState()
            ensureEntryKeys(context: context)
            let localBefore = localRows(context: context, state: &state)
            saveState(state)

            let changes = buildChanges(local: localBefore, snapshot: state.snapshot)
            if !changes.isEmpty {
                let resp = try await post(["action": "sync_push", "changes": changes])
                if let status = resp["status"] as? String, status != "ok" {
                    throw SyncError.badResponse("Home server did not accept the changes.")
                }
            }

            let server = try await pullAll()
            let changed = !changes.isEmpty || server != state.snapshot
            apply(server: server, localBefore: localBefore, state: &state, context: context)
            ownSave(context)
            state.snapshot = server
            saveState(state)
            finish(error: nil)
            if changed || !EmergencyCopyService.hasCopy { await writeEmergencyCopy(context: context) }
        } catch {
            finish(error: error.localizedDescription)
        }
    }

    private func finish(error: String?) {
        if error == nil {
            let now = Date()
            HomeServerSettings.lastSync = now
            lastSync = now
        }
        HomeServerSettings.lastError = error
        lastError = error
    }

    /// Full backup of all local data in the home server table format (can be re-imported).
    func fullBackupJSON(context: ModelContext) throws -> Data {
        ensureEntryKeys(context: context)
        var state = loadState()
        let rows = localRows(context: context, state: &state)
        var tables: [String: [[String: String]]] = [:]
        for (table, byId) in rows {
            tables[table] = byId.map { id, row in var r = row; r["id"] = id; return r }
                .sorted { ($0["id"] ?? "") < ($1["id"] ?? "") }
        }
        let obj: [String: Any] = [
            "format": "purus-health-backup",
            "version": 1,
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "tables": tables
        ]
        return try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    }

    private func writeEmergencyCopy(context: ModelContext) async {
        let records = (try? context.fetch(FetchDescriptor<MedicalRecord>())) ?? []
        do {
            let backup = try fullBackupJSON(context: context)
            try await EmergencyCopyService.writeEmergencyCopy(records: records.filter { !$0.isMarkedForDeletion }, backup: backup)
        } catch {
            ShareDebugStore.shared.appendLog("HomeServer: emergency copy failed: \(error)")
        }
    }

    // MARK: - Network

    private func post(_ body: [String: Any]) async throws -> [String: Any] {
        guard let url = HomeServerSettings.apiURL else { throw SyncError.noURL }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = HomeServerSettings.deviceKey
        if !key.isEmpty { req.setValue(key, forHTTPHeaderField: "X-Device-Key") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw SyncError.http(code) }
        if data.isEmpty { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else {
            throw SyncError.badResponse("Home server sent an unreadable answer.")
        }
        if let dict = obj as? [String: Any] { return dict }
        if let arr = obj as? [[String: Any]], let first = arr.first { return first }
        return [:]
    }

    /// Fetches all data. Result: [table: [id: canonical row incl. profile_id]].
    private func pullAll() async throws -> Snapshot {
        let resp = try await post(["action": "pull_all"])
        guard resp["profiles"] is [Any] else {
            throw SyncError.badResponse("Home server does not support full fetch yet (Health API workflow needs the update).")
        }
        var out = Snapshot()
        for table in allTables {
            var rows: [String: HSRow] = [:]
            for raw in (resp[table] as? [[String: Any]]) ?? [] {
                guard let id = (raw["id"] as? String)?.lowercased() else { continue }
                var row = HSRow()
                for (k, v) in raw { row[k] = HSValue.canonical(column: k, raw: v) }
                row["id"] = id
                if let pid = row["profile_id"] { row["profile_id"] = pid.lowercased() }
                rows[id] = row
            }
            out[table] = rows
        }
        return out
    }

    // MARK: - Local rows

    private var entryTypes: [any HomeServerEntry.Type] {
        [BloodEntry.self, DrugEntry.self, VaccinationEntry.self, AllergyEntry.self, IllnessEntry.self,
         RiskEntry.self, MedicalHistoryEntry.self, MedicalDocumentEntry.self, WeightEntry.self,
         HumanDoctorEntry.self, EmergencyContact.self, PetYearlyCostEntry.self]
    }

    private var allTables: [String] {
        [profileTable, personalTable, petTable] + entryTypes.map { $0.table }
    }

    private func liveRecords(_ context: ModelContext) -> [MedicalRecord] {
        ((try? context.fetch(FetchDescriptor<MedicalRecord>())) ?? []).filter { !$0.isMarkedForDeletion }
    }

    /// Gives every entry a unique UUID key (entries created before home server mode have none).
    private func ensureEntryKeys(context: ModelContext) {
        let records = liveRecords(context)
        for type in entryTypes { ensureKeys(type, records: records) }
        ownSave(context)
    }

    private func ownSave(_ context: ModelContext) {
        guard context.hasChanges else { return }
        ignoreSavesUntil = Date().addingTimeInterval(1.5)
        try? context.save()
    }

    private func ensureKeys<T: HomeServerEntry>(_ type: T.Type, records: [MedicalRecord]) {
        var seen = Set<String>()
        for r in records {
            for e in T.entries(of: r) {
                var entry = e
                let k = entry.syncKey.lowercased()
                if !HSValue.isUUID(k) || seen.contains(k) {
                    entry.syncKey = UUID().uuidString.lowercased()
                }
                seen.insert(entry.syncKey.lowercased())
            }
        }
    }

    /// Local data as canonical rows: [table: [id: row]] (managed columns + profile_id).
    private func localRows(context: ModelContext, state: inout SyncState) -> Snapshot {
        var out = Snapshot()
        for t in allTables { out[t] = [:] }
        for r in liveRecords(context) {
            let pid = r.uuid.lowercased()
            guard HSValue.isUUID(pid) else { continue }
            out[profileTable]?[pid] = ["is_pet": r.isPet ? "true" : "false"]
            let infoTable = r.isPet ? petTable : personalTable
            let infoId = state.infoId(for: pid, pet: r.isPet)
            var info = r.isPet ? HSProfile.pet(r) : HSProfile.personal(r)
            info["profile_id"] = pid
            out[infoTable]?[infoId] = info
            for type in entryTypes { addRows(type, record: r, pid: pid, into: &out) }
        }
        return out
    }

    private func addRows<T: HomeServerEntry>(_ type: T.Type, record: MedicalRecord, pid: String, into out: inout Snapshot) {
        for e in T.entries(of: record) {
            var row = e.canonical()
            row["profile_id"] = pid
            out[T.table]?[e.syncKey.lowercased()] = row
        }
    }

    /// Server row in the same canonical form as local rows (only columns the app manages).
    private func canonicalServer(table: String, row: HSRow) -> HSRow {
        var out: HSRow
        switch table {
        case profileTable: out = ["is_pet": row["is_pet"] ?? "false"]
        case personalTable: out = HSRow(uniqueKeysWithValues: HSProfile.personalColumns.map { ($0, row[$0] ?? "") })
        case petTable: out = HSRow(uniqueKeysWithValues: HSProfile.petColumns.map { ($0, row[$0] ?? "") })
        default:
            if let type = entryTypes.first(where: { $0.table == table }) {
                out = type.canonicalFromServer(row)
            } else {
                out = [:]
            }
        }
        if table != profileTable { out["profile_id"] = row["profile_id"] ?? "" }
        return out
    }

    // MARK: - Diff

    private func buildChanges(local: Snapshot, snapshot: Snapshot) -> [[String: Any]] {
        var upserts: [[String: Any]] = []
        var deletes: [[String: Any]] = []
        let now = ISO8601DateFormatter().string(from: Date())

        for table in allTables {
            let localT = local[table] ?? [:]
            let snapT = snapshot[table] ?? [:]
            for (id, row) in localT {
                let prev = snapT[id]
                if let prev, canonicalServer(table: table, row: prev) == row { continue }
                var cols = row
                if let type = entryTypes.first(where: { $0.table == table }) {
                    let pid = cols.removeValue(forKey: "profile_id")
                    cols = type.dbColumns(from: cols, previousServerRow: prev)
                    if let pid { cols["profile_id"] = pid }
                }
                var data: [String: Any] = ["id": id]
                for (k, v) in cols { data[k] = (k == "profile_id") ? v : HSValue.dbValue(column: k, canonical: v) }
                if table == profileTable { data["active"] = true }
                upserts.append([
                    "id": UUID().uuidString.lowercased(), "store": table, "recordId": id,
                    "action": prev == nil ? "insert" : "update", "data": data,
                    "timestamp": now, "synced": 0, "clear_empty": true
                ])
            }
            // Person / pet info rows are removed with their profile on the server; never delete them alone.
            if table == personalTable || table == petTable { continue }
            for id in snapT.keys where localT[id] == nil {
                deletes.append([
                    "id": UUID().uuidString.lowercased(), "store": table, "recordId": id,
                    "action": "delete", "timestamp": now, "synced": 0
                ])
            }
        }
        // Profiles first on insert (children reference them); children first on delete.
        let order = Dictionary(uniqueKeysWithValues: allTables.enumerated().map { ($1, $0) })
        upserts.sort { (order[$0["store"] as! String] ?? 0) < (order[$1["store"] as! String] ?? 0) }
        deletes.sort { (order[$0["store"] as! String] ?? 0) > (order[$1["store"] as! String] ?? 0) }
        return upserts + deletes
    }

    // MARK: - Apply server data

    /// Applies server data. `localBefore == nil` means full replace (first connect).
    /// Otherwise entries edited on the phone while the sync was running are left alone.
    private func apply(server: Snapshot, localBefore: Snapshot?, state: inout SyncState, context: ModelContext) {
        let replace = localBefore == nil
        var localNow = Snapshot()
        if !replace { localNow = localRows(context: context, state: &state) }

        func editedDuringSync(_ table: String, _ id: String) -> Bool {
            guard let before = localBefore else { return false }
            return before[table]?[id] != localNow[table]?[id]
        }

        var recordsById: [String: MedicalRecord] = [:]
        for r in liveRecords(context) { recordsById[r.uuid.lowercased()] = r }

        // Profiles + personal / pet info
        let serverProfilesById = server[profileTable] ?? [:]
        let infoByProfile: [String: (table: String, id: String, row: HSRow)] = {
            var m: [String: (String, String, HSRow)] = [:]
            for t in [personalTable, petTable] {
                for (id, row) in server[t] ?? [:] {
                    guard let pid = row["profile_id"], let p = serverProfilesById[pid] else { continue }
                    // Use the info table that matches the profile type
                    let isPet = p["is_pet"] == "true"
                    if (t == petTable) == isPet { m[pid] = (t, id, row) }
                }
            }
            return m
        }()

        for (pid, prow) in server[profileTable] ?? [:] {
            let isPet = prow["is_pet"] == "true"
            let record: MedicalRecord
            if let existing = recordsById[pid] {
                record = existing
            } else {
                record = MedicalRecord(uuid: pid, isPet: isPet)
                context.insert(record)
                recordsById[pid] = record
            }
            if !editedDuringSync(profileTable, pid), record.isPet != isPet { record.isPet = isPet }
            if let info = infoByProfile[pid] {
                state.setInfoId(info.id, for: pid, pet: info.table == petTable)
                if !editedDuringSync(info.table, info.id) {
                    var canon = canonicalServer(table: info.table, row: info.row)
                    canon.removeValue(forKey: "profile_id")
                    let current = info.table == petTable ? HSProfile.pet(record) : HSProfile.personal(record)
                    if current != canon {
                        if info.table == petTable { HSProfile.applyPet(canon, to: record) } else { HSProfile.applyPersonal(canon, to: record) }
                        record.updatedAt = Date()
                    }
                }
            }
        }

        // Entries
        for type in entryTypes {
            applyEntries(type, server: server[type.table] ?? [:], recordsById: recordsById,
                         replace: replace, localBefore: localBefore, editedDuringSync: editedDuringSync, context: context)
        }

        // Records no longer on the server
        let serverProfiles = server[profileTable] ?? [:]
        for (pid, record) in recordsById where serverProfiles[pid] == nil {
            if replace {
                context.delete(record)
            } else if localBefore?[profileTable]?[pid] != nil, !editedDuringSync(profileTable, pid) {
                context.delete(record)
            }
        }
    }

    private func applyEntries<T: HomeServerEntry>(
        _ type: T.Type, server: [String: HSRow], recordsById: [String: MedicalRecord],
        replace: Bool, localBefore: Snapshot?, editedDuringSync: (String, String) -> Bool, context: ModelContext
    ) {
        var localByKey: [String: T] = [:]
        for r in recordsById.values { for e in T.entries(of: r) { localByKey[e.syncKey.lowercased()] = e } }

        for (id, row) in server {
            guard let pid = row["profile_id"], let record = recordsById[pid] else { continue }
            let canon = T.canonicalFromServer(row)
            if var existing = localByKey[id] {
                if editedDuringSync(T.table, id) { continue }
                if existing.canonical() != canon { existing.apply(canon) }
            } else {
                var e = T.make(for: record, in: context)
                e.syncKey = id
                e.apply(canon)
            }
        }

        for (id, e) in localByKey where server[id] == nil {
            if replace {
                context.delete(e)
            } else if localBefore?[T.table]?[id] != nil, !editedDuringSync(T.table, id) {
                context.delete(e)
            }
        }
    }

    // MARK: - State

    typealias Snapshot = [String: [String: HSRow]]

    struct SyncState: Codable {
        var snapshot: Snapshot = [:]
        var personalInfoIds: [String: String] = [:]
        var petInfoIds: [String: String] = [:]

        mutating func infoId(for pid: String, pet: Bool) -> String {
            if let id = pet ? petInfoIds[pid] : personalInfoIds[pid] { return id }
            let id = UUID().uuidString.lowercased()
            setInfoId(id, for: pid, pet: pet)
            return id
        }

        mutating func setInfoId(_ id: String, for pid: String, pet: Bool) {
            if pet { petInfoIds[pid] = id } else { personalInfoIds[pid] = id }
        }
    }

    private var stateURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HomeServer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync-state.json")
    }

    private func loadState() -> SyncState {
        guard let data = try? Data(contentsOf: stateURL),
              let s = try? JSONDecoder().decode(SyncState.self, from: data) else { return SyncState() }
        return s
    }

    private func saveState(_ s: SyncState) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: stateURL, options: [.atomic, .completeFileProtection])
    }

    private func clearState() {
        try? FileManager.default.removeItem(at: stateURL)
    }
}
