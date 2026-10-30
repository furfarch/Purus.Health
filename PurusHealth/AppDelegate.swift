#if canImport(UIKit)
import Foundation
import UIKit
import CloudKit

// Scene delegate to handle modern URL / userActivity delivery (iOS 13+ scenes)
@objc
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    // Called when app is COLD LAUNCHED (not running) - share data comes through options
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        let urlCount = connectionOptions.urlContexts.count
        let activityCount = connectionOptions.userActivities.count
        ShareDebugStore.shared.appendLog("SceneDelegate: willConnectTo called, urlContexts=\(urlCount), userActivities=\(activityCount)")

        // Face ID lock screen is up before the first frame
        if let windowScene = scene as? UIWindowScene {
            MainActor.assumeIsolated { AppLock.shared.attach(windowScene) }
        }

        // Check for share URL in URL contexts (cold launch via URL scheme)
        for context in connectionOptions.urlContexts {
            if HomeServerPairing.isPairingURL(context.url) {
                // wait until the SwiftUI view listens for the result
                let url = context.url
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { HomeServerPairing.handle(url: url) }
                continue
            }
            handleShareURL(context.url)
        }

        // Check for share in user activities (cold launch via universal link or CloudKit share)
        for userActivity in connectionOptions.userActivities {
            handleUserActivity(userActivity)
        }
    }

    // Called when app is ALREADY RUNNING and receives a URL
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // Home server pairing link (QR code from purus.HEALTH web) - handled here, never as a share
        var URLContexts = URLContexts
        for context in URLContexts where HomeServerPairing.handle(url: context.url) { URLContexts.remove(context) }
        if URLContexts.isEmpty { return }
        ShareDebugStore.shared.appendLog("SceneDelegate: openURLContexts called, count=\(URLContexts.count)")
        for context in URLContexts {
            handleShareURL(context.url)
        }
    }

    // Called when app is ALREADY RUNNING and receives a user activity (universal link, CloudKit share)
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        ShareDebugStore.shared.appendLog("SceneDelegate: continue userActivity called, type=\(userActivity.activityType)")
        handleUserActivity(userActivity)
    }

    private func handleShareURL(_ url: URL) {
        ShareDebugStore.shared.appendLog("SceneDelegate: received URL: \(url.absoluteString)")
        PendingShareStore.shared.pendingURL = url
        postPendingShare(["url": url])
    }

    private func postPendingShare(_ userInfo: [String: Any]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NotificationNames.pendingShareReceived, object: nil, userInfo: userInfo)
        }
    }

    private func handleUserActivity(_ userActivity: NSUserActivity) {
        ShareDebugStore.shared.appendLog("SceneDelegate: received userActivity type: \(userActivity.activityType)")

        // Check for CloudKit share metadata (available iOS 10+)
        if let metadata = extractCloudKitMetadata(from: userActivity) {
            ShareDebugStore.shared.appendLog("SceneDelegate: found cloudKitShareMetadata, container: \(metadata.containerIdentifier)")
            PendingShareStore.shared.pendingMetadata = metadata
            postPendingShare(["metadata": metadata])
            return
        }

        // Fall back to webpage URL (universal links)
        if let url = userActivity.webpageURL {
            ShareDebugStore.shared.appendLog("SceneDelegate: found webpageURL: \(url.absoluteString)")
            handleShareURL(url)
        }
    }

    private func extractCloudKitMetadata(from userActivity: NSUserActivity) -> CKShare.Metadata? {
        // Use Key-Value coding to access cloudKitShareMetadata safely
        // This avoids compilation issues with the property not being found
        return userActivity.value(forKey: "cloudKitShareMetadata") as? CKShare.Metadata
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        ShareDebugStore.shared.appendLog("SceneDelegate: userDidAcceptCloudKitShareWith (SceneDelegate) called")
        PendingShareStore.shared.pendingMetadata = metadata
        postPendingShare(["metadata": metadata])
    }
}

@objc
class AppDelegate: UIResponder, UIApplicationDelegate {
    // Provide a scene configuration that uses `SceneDelegate` as the scene's delegate class.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    // Scene-based app: share links, user activities and accepted CloudKit shares arrive in SceneDelegate.

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        ShareDebugStore.shared.appendLog("AppDelegate: didReceiveRemoteNotification")
        // Post a notification so views can refresh shared/private records
        NotificationCenter.default.post(name: NotificationNames.didChangeSharedRecords, object: nil)
        completionHandler(.newData)
    }
}
#endif

