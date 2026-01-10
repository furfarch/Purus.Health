import Foundation
import SwiftUI
import Combine

/// Small in-app debug store for CloudKit sharing operations.
@MainActor
final class ShareDebugStore: ObservableObject {
    static let shared = ShareDebugStore()

    @Published var logs: [String] = []
    @Published var lastShareURL: URL? = nil
    @Published var lastError: Error? = nil

    private let maxEntries = 200
    private let filename = "share_debug.log"

    private init() {
        loadFromDisk()
    }

    private var fileURL: URL? {
        do {
            let fm = FileManager.default
            let dir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let appDir = dir.appendingPathComponent(Bundle.main.bundleIdentifier ?? "MyHealthData")
            if !fm.fileExists(atPath: appDir.path) { try fm.createDirectory(at: appDir, withIntermediateDirectories: true) }
            return appDir.appendingPathComponent(filename)
        } catch {
            print("ShareDebugStore: failed to locate Application Support: \(error)")
            return nil
        }
    }

    func appendLog(_ text: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(text)"
        logs.append(line)
        // keep recent entries
        if logs.count > maxEntries {
            logs.removeFirst(logs.count - maxEntries)
        }
        saveToDisk()
    }

    func clear() {
        logs.removeAll()
        lastShareURL = nil
        lastError = nil
        saveToDisk()
    }

    func exportText() -> String {
        var parts: [String] = []
        parts.append("Share Debug Export")
        parts.append("Timestamp: \(ISO8601DateFormatter().string(from: Date()))")
        if let url = lastShareURL {
            parts.append("LastShareURL: \(url.absoluteString)")
        }
        if let err = lastError {
            parts.append("LastError: \(String(describing: err))")
        }
        parts.append("\nLogs:\n")
        parts.append(logs.joined(separator: "\n"))
        return parts.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func saveToDisk() {
        guard let url = fileURL else { return }
        let export = exportText()
        do {
            try export.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("ShareDebugStore: failed to write logs to disk: \(error)")
        }
    }

    private func loadFromDisk() {
        guard let url = fileURL else { return }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            // Heuristic: take the last maxEntries lines as logs
            let lines = content.components(separatedBy: .newlines)
            // Find the index where "Logs:" header starts
            if let logsIndex = lines.firstIndex(where: { $0.contains("Logs:") }) {
                let logLines = Array(lines.suffix(from: logsIndex + 1))
                let last = logLines.suffix(maxEntries)
                self.logs = Array(last)
            } else {
                // If not structured, just load last lines
                self.logs = Array(lines.suffix(maxEntries))
            }
        } catch {
            // no existing file is fine
        }
    }
}
