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
        get {
            if !accessibilityUpdated {
                accessibilityUpdated = true
                // keys saved by older builds: keep them, only make them device-only (no backup / device transfer)
                SecItemUpdate(baseQuery(keychainAccount) as CFDictionary,
                              [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary)
            }
            return readKeychain(account: keychainAccount) ?? ""
        }
        set { writeKeychain(newValue, account: keychainAccount) }
    }

    private static var accessibilityUpdated = false

    /// Same rule as pairing: only https addresses with a host.
    static func isValidServer(_ s: String) -> Bool {
        guard let u = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return u.scheme == "https" && u.host != nil
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
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}

/// Pairing with the home server (KB Home devices). The code comes from Home › Devices:
/// QR code = purushealth://pair?code=ph1.<key>&server=<https API address> (opened by the Camera app), or the pasted code.
enum HomeServerPairing {
    static let didPair = Notification.Name("homeServer.didPair")
    /// A pairing link arrived; it waits in `pending` until the user confirms it (after Face ID).
    static let linkReceived = Notification.Name("homeServer.pairLinkReceived")
    private static var lastCode = ""
    private static var lastTime = Date.distantPast
    private(set) static var pending: (code: String, server: String?)?

    static func isPairingURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "purushealth" && url.host?.lowercased() == "pair"
    }

    /// Handles a pairing link; returns false for any other URL. A valid link is only queued (see `confirmPending`),
    /// an invalid one is reported via `didPair` (ok: false).
    @discardableResult
    static func handle(url: URL) -> Bool {
        guard isPairingURL(url) else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let code = items.first { $0.name == "code" }?.value ?? ""
        // the same link can arrive twice (scene delegate and SwiftUI); handle it once
        if code == lastCode && Date().timeIntervalSince(lastTime) < 5 { return true }
        lastCode = code
        lastTime = Date()
        guard key(from: code) != nil else {
            NotificationCenter.default.post(name: didPair, object: nil, userInfo: ["ok": false])
            return true
        }
        let server = items.first { $0.name == "server" }?.value
        pending = (code, server.flatMap { HomeServerSettings.isValidServer($0) ? $0 : nil })
        NotificationCenter.default.post(name: linkReceived, object: nil)
        return true
    }

    /// Server host the pending link would pair with (its own server, else the current one).
    static var pendingHost: String? {
        guard let p = pending else { return nil }
        return URL(string: p.server ?? "")?.host ?? HomeServerSettings.apiURL?.host ?? ""
    }

    /// User confirmed the pending link: pair now and report via `didPair`.
    static func confirmPending() {
        guard let p = pending else { return }
        pending = nil
        let ok = pair(code: p.code, server: p.server)
        NotificationCenter.default.post(name: didPair, object: nil, userInfo: ["ok": ok])
    }

    static func cancelPending() { pending = nil }

    private static func key(from code: String) -> String? {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard c.hasPrefix("ph1.") else { return nil }
        let key = String(c.dropFirst(4))
        return key.range(of: "^[A-Za-z0-9_-]{40,100}$", options: .regularExpression) != nil ? key : nil
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
        guard let key = key(from: code) else { return false }
        if let server, HomeServerSettings.isValidServer(server) {
            HomeServerSettings.urlString = server
        }
        HomeServerSettings.deviceKey = key
        HomeServerSettings.pairedAt = Date()
        HomeServerSettings.removeOldAppKey()
        return true
    }
}
