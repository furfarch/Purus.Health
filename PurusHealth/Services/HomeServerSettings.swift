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
    private static let keychainAccount = "homeServer.deviceKey"
    private static let oldKeychainAccount = "homeServer.appKey"   // fixed app key of the first 1.4 build, no longer used
    private static let pairedAtKey = "homeServer.pairedAt"

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

    /// Device key from pairing (Home › Devices), sent as `X-Device-Key` header on every call.
    static var deviceKey: String {
        get { readKeychain(account: keychainAccount) ?? "" }
        set { writeKeychain(newValue, account: keychainAccount) }
    }

    static var isPaired: Bool { !deviceKey.isEmpty }

    static var pairedAt: Date? {
        get { UserDefaults.standard.object(forKey: pairedAtKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: pairedAtKey) }
    }

    /// Web page where a device is added: Home › Devices (central device management, KB Home devices).
    static var addDeviceURL: URL? {
        URL(string: "https://home.ds8152f54.synology.me/devices.html")
    }

    static func unpair() {
        deviceKey = ""
        pairedAt = nil
    }

    fileprivate static func removeOldAppKey() { writeKeychain("", account: oldKeychainAccount) }

    // MARK: - Keychain

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.Info.bundleID,
            kSecAttrAccount as String: account
        ]
    }

    private static func readKeychain(account: String) -> String? {
        var q = baseQuery(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ value: String, account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
        guard !value.isEmpty else { return }
        var q = baseQuery(account)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}

/// Pairing with the home server (KB Home devices). The code comes from Home › Devices:
/// QR code = purushealth://pair?code=ph1.<key>&server=<https API address> (opened by the Camera app), or the pasted code.
enum HomeServerPairing {
    static let didPair = Notification.Name("homeServer.didPair")
    private static var lastCode = ""
    private static var lastTime = Date.distantPast

    static func isPairingURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "purushealth" && url.host?.lowercased() == "pair"
    }

    /// Handles a pairing link; returns false for any other URL. Shows the result via `didPair` (ok: Bool).
    @discardableResult
    static func handle(url: URL) -> Bool {
        guard isPairingURL(url) else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let code = items.first { $0.name == "code" }?.value ?? ""
        // the same link can arrive twice (scene delegate and SwiftUI); handle it once
        if code == lastCode && Date().timeIntervalSince(lastTime) < 5 { return true }
        lastCode = code
        lastTime = Date()
        let ok = pair(code: code, server: items.first { $0.name == "server" }?.value)
        NotificationCenter.default.post(name: didPair, object: nil, userInfo: ["ok": ok])
        return true
    }

    /// Pasted text: the code itself or the whole pairing link.
    static func pair(text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: t), isPairingURL(url) {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return pair(code: items.first { $0.name == "code" }?.value ?? "", server: items.first { $0.name == "server" }?.value)
        }
        return pair(code: t, server: nil)
    }

    static func pair(code: String, server: String?) -> Bool {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard c.hasPrefix("ph1.") else { return false }
        let key = String(c.dropFirst(4))
        guard key.range(of: "^[A-Za-z0-9_-]{40,100}$", options: .regularExpression) != nil else { return false }
        if let server, let u = URL(string: server), u.scheme == "https", u.host != nil {
            HomeServerSettings.urlString = server
        }
        HomeServerSettings.deviceKey = key
        HomeServerSettings.pairedAt = Date()
        HomeServerSettings.removeOldAppKey()
        return true
    }
}
