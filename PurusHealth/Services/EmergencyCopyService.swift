import Foundation

/// Writes the emergency copy to iCloud Drive (folder "Purus Health"):
/// one PDF per record plus a full JSON backup. Falls back to the app's own
/// Documents folder (Files app > On My iPhone) when iCloud Drive is not available.
enum EmergencyCopyService {
    private static let lastWriteKey = "homeServer.emergencyCopyWritten"

    static var hasCopy: Bool { UserDefaults.standard.object(forKey: lastWriteKey) != nil }

    static var lastWrite: Date? { UserDefaults.standard.object(forKey: lastWriteKey) as? Date }

    /// Base folder: iCloud Drive app folder if available, else local Documents.
    static func baseFolder() async -> URL {
        let cloud: URL? = await Task.detached(priority: .utility) {
            FileManager.default.url(forUbiquityContainerIdentifier: AppConfig.CloudKit.containerID)
        }.value
        if let cloud {
            return cloud.appendingPathComponent("Documents", isDirectory: true)
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func folderDescription() async -> String {
        let cloud: URL? = await Task.detached(priority: .utility) {
            FileManager.default.url(forUbiquityContainerIdentifier: AppConfig.CloudKit.containerID)
        }.value
        return cloud != nil ? "iCloud Drive › Purus Health" : "On My iPhone › Purus Health"
    }

    /// Writes a one-off JSON backup of all records, e.g. before replacing phone data.
    @MainActor
    static func writeBackup(data: Data, prefix: String) async throws -> URL {
        let folder = await baseFolder().appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = fileStamp()
        let url = folder.appendingPathComponent("\(prefix) \(stamp).json")
        try data.write(to: url, options: .atomic)
        // keep only the newest 3 of this kind (the stamp in the name sorts by time)
        let old = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(prefix + " ") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .dropFirst(3)
        for u in old { try? FileManager.default.removeItem(at: u) }
        return url
    }

    /// Emergency copy: PDF per record + full JSON backup. Replaces the previous copy.
    @MainActor
    static func writeEmergencyCopy(records: [MedicalRecord], backup: Data) async throws {
        // never replace a copy with nothing: an empty set is kept as the last good copy
        guard !records.isEmpty else { return }
        let folder = await baseFolder().appendingPathComponent("Emergency", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        try backup.write(to: folder.appendingPathComponent("Purus Health - all records.json"), options: .atomic)

        var written = Set<String>()
        for record in records.sorted(by: { ($0.sortKey, $0.uuid) < ($1.sortKey, $1.uuid) }) {
            var name = safeFileName(record.displayName)
            if written.contains(name) { name += " " + String(record.uuid.prefix(4)) }
            written.insert(name)
            let pdf = try await ExportService.makePDFData(for: record)
            try pdf.write(to: folder.appendingPathComponent("\(name).pdf"), options: .atomic)
        }

        // Remove PDFs of records that no longer exist
        let existing = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in existing where url.pathExtension == "pdf" {
            if !written.contains(url.deletingPathExtension().lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        }
        UserDefaults.standard.set(Date(), forKey: lastWriteKey)
    }

    private static func fileStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH-mm"
        return f.string(from: Date())
    }

    private static func safeFileName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Record" : cleaned
    }
}
