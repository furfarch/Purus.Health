// SharedImportSuppression.swift
// Utility to locally suppress re-import of specific shared records by uuid.

import Foundation

struct SharedImportSuppression {
    private static let key = "SuppressedSharedUUIDs"

    static func isSuppressed(_ uuid: String) -> Bool {
        let set = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
        return set.contains(uuid)
    }

    static func suppress(_ uuid: String) {
        var set = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
        if !set.contains(uuid) {
            set.append(uuid)
            UserDefaults.standard.set(set, forKey: key)
        }
    }

    static func clear(_ uuid: String) {
        var set = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
        if let idx = set.firstIndex(of: uuid) {
            set.remove(at: idx)
            UserDefaults.standard.set(set, forKey: key)
        }
    }
}
