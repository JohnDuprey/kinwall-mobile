import Foundation
import Security

/// A link for the web app from native code in the app's process (Siri's and the Controls' App
/// Intents, native/ios/OpenIntents.swift): kept until JavaScript takes it (src/App.tsx), so one
/// that arrives while the app is still starting isn't lost, and announced to a running one. Also what
/// the share sheet left to check (KinwallKit AppSignIn.leaveForApp, in the shared Keychain group),
/// when it was left within the hour.
public enum PendingLink {
    static let posted = Notification.Name("KinwallPendingLink")
    private static let lock = NSLock()
    nonisolated(unsafe) private static var link: String?

    public static func open(_ link: String) {
        lock.withLock { self.link = link }
        NotificationCenter.default.post(name: posted, object: nil)
    }

    static func take() -> String? { lock.withLock { defer { link = nil }; return link } ?? fromShareSheet() }

    private static func fromShareSheet() -> String? {
        var q = Keychain.query("family.kinwall.link", true)
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        SecItemDelete(Keychain.query("family.kinwall.link", true) as CFDictionary)
        guard let left = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let at = left["at"] as? Double,
              Date.now.timeIntervalSince1970 - at < 3600 else { return nil }
        return left["link"] as? String
    }
}
