import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Per-record export UI housed in Settings.
struct ExportRecordSheet: View {
    let record: MedicalRecord

    @Environment(\.dismiss) private var dismiss

    @State private var exportErrorMessage: String?
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Export") {
                    Button("Export JSON") { Task { await exportJSON() } }
                    Button("Export HTML") { Task { await exportHTML() } }
                    Button("Export PDF") { Task { await exportPDF() } }
                }

                if let exportErrorMessage {
                    Section("Error") {
                        Text(exportErrorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Export")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } }),
                document: exportURL.map { ExportFileDocument(fileURL: $0) },
                contentType: .data,
                defaultFilename: exportURL?.lastPathComponent ?? "export"
            ) { _ in }
            // Medical data must not linger in tmp once the exporter is closed.
            .onChange(of: exportURL) { old, _ in
                if let old { try? FileManager.default.removeItem(at: old) }
            }
        }
    }

    private func exportJSON() async {
        await export(type: "json") {
            try ExportService.makeJSONData(for: record)
        }
    }

    private func exportHTML() async {
        await export(type: "html") {
            Data(ExportService.makeHTMLString(for: record).utf8)
        }
    }

    private func exportPDF() async {
        exportErrorMessage = nil
        do {
            let data = try await ExportService.makePDFData(for: record)
            try await writeExport(data: data, type: "pdf")
        } catch {
            exportErrorMessage = "Export PDF failed: \(error.localizedDescription)"
        }
    }

    private func export(type: String, makeData: () throws -> Data) async {
        exportErrorMessage = nil
        do {
            let data = try makeData()
            try await writeExport(data: data, type: type)
        } catch {
            exportErrorMessage = "Export \(type.uppercased()) failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func writeExport(data: Data, type: String) async throws {
        let safeName = record.displayName.replacingOccurrences(of: "/", with: "-")
        let fileName = "\(safeName.isEmpty ? "MedicalRecord" : safeName).\(type)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        exportURL = url
    }


}
