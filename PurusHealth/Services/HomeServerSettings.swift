import Foundation
import Security

/// Settings for the optional home server mode.
/// When enabled, the home server is the main copy of all records and iCloud sync is paused.
enum HomeServerSettings {
    static let defaultURL = "https://purushealth.ds8152f54.synology.me/health/api/"

    private static let enabledKey = "homeServer.enabled"
    private static let urlKey = "homeServer.url"
    private static let lastSyncKey = "homeServer.lastSync"
    private static let lastErrorKey = "homeServer.lastError"
    private static let keychainAccount = "homeServer.appKey"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var urlString: String {
        get { UserDefaults.standard.string(forKey: urlKey) ?? defaultURL }
        set { UserDefaults.standard.set(newValue, forKey: urlKey) }
    }

    /// API URL with a guaranteed trailing slash (nginx drops POST bodies on the 301 redirect otherwise).
    static var apiURL: URL? {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.hasSuffix("/") { s += "/" }
        return URL(string: s)
    }

    static var lastSync: Date? {
        get { UserDefaults.standard.object(forKey: lastSyncKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncKey) }
    }

    static var lastError: String? {
        get { UserDefaults.standard.string(forKey: lastErrorKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastErrorKey) }
    }

    /// Optional app key, sent as `X-App-Key` header (used for access from outside home).
    static var appKey: String {
        get { readKeychain() ?? "" }
        set { writeKeychain(newValue) }
    }

    // MARK: - Keychain

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.Info.bundleID,
            kSecAttrAccount as String: keychainAccount
        ]
    }

    private static func readKeychain() -> String? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ value: String) {
        SecItemDelete(baseQuery() as CFDictionary)
        guard !value.isEmpty else { return }
        var q = baseQuery()
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
