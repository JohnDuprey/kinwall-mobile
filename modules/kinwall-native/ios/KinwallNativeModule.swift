import ExpoModulesCore
import WidgetKit
import WatchConnectivity
import Security
import ActivityKit

/// What the shell can't do from JavaScript: reload the widgets' timelines, hand the Watch its key
/// over WatchConnectivity (src/sharedKey.ts mints it; targets/watch keeps it), and keep keys in
/// the Keychain exactly as KinwallKit's KeychainConnectionStore does (expo-secure-store adds a
/// suffix to the service name, which the widgets, Watch and Siri wouldn't find).
public class KinwallNativeModule: Module {
    private let watch = WatchBridge()

    public func definition() -> ModuleDefinition {
        Name("KinwallNative")
        Events("watchStateChanged", "activityToken", "link")
        OnCreate {
            NotificationCenter.default.addObserver(forName: PendingLink.posted, object: nil, queue: .main) { [weak self] _ in self?.sendEvent("link") }
            self.watch.onChange = { [weak self] in self?.sendEvent("watchStateChanged") }
            self.watch.start()
            LiveActivities.watchPush { [weak self] token in self?.sendEvent("activityToken", token) }
        }
        /// Live Activities (LiveActivities.swift): `payload` is the web app's JSON for that kind; a
        /// cooking one also sets its timers' alarms (CookingAlarms.swift).
        /// `colors` the family's (#RRGGBB bg, fg, accent), or nil for Kinwall's.
        AsyncFunction("activitySet") { (kind: String, payload: String, colors: [String: String]?) in
            if kind == "cooking" { await CookingAlarms.set(json: payload, accent: colors?["accent"]) } // rings even with Live Activities off, in the family's accent
            let theme = colors.flatMap { c in c["bg"].flatMap { bg in c["fg"].flatMap { fg in c["accent"].map { KinwallActivityAttributes.Colors(bg: bg, fg: fg, accent: $0) } } } }
            try await LiveActivities.set(kind: kind, json: payload, colors: theme) { [weak self] token in self?.sendEvent("activityToken", token) }
        }
        AsyncFunction("activityEnd") { (kind: String?) in
            if kind == nil || kind == "cooking" { await CookingAlarms.clear() }
            if let kind { await LiveActivities.end(kind: kind) } else { await LiveActivities.endAll() }
        }
        AsyncFunction("activityEndStale") { await LiveActivities.endStale() }
        /// After src/reminders.ts schedules: the Focus tag and Time Sensitive (Reminders.swift).
        AsyncFunction("tagReminders") { await Reminders.tag() }
        /// Off in iPhone Settings → Kinwall → Live Activities (the web app says so in its Notifications section).
        Function("activitiesEnabled") { ActivityAuthorizationInfo().areActivitiesEnabled }
        /// `shared`: the group the widgets, Watch and Siri read (SharedKeychain.group).
        AsyncFunction("keychainGet") { (service: String, shared: Bool) -> String? in
            var q = Keychain.query(service, shared)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        /// Kept on this iPhone only: sign-ins and keys never go into a backup or onto another phone.
        AsyncFunction("keychainSet") { (service: String, shared: Bool, value: String?) in
            let q = Keychain.query(service, shared)
            guard let value else { SecItemDelete(q as CFDictionary); return }
            let attrs: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            var status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
            if status == errSecItemNotFound { status = SecItemAdd(q.merging(attrs) { $1 } as CFDictionary, nil) }
            if status != errSecSuccess { throw Exception(name: "KeychainError", description: "Keychain status \(status)") }
        }
        /// Spotlight (Spotlight.swift): replace the family's items, or clear them on sign-out.
        AsyncFunction("spotlightSet") { (items: [[String: String]]) in try await Spotlight.replace(items) }
        AsyncFunction("spotlightClear") { try await Spotlight.clear() }
        /// A link an App Intent left for the web app (PendingLink), once.
        Function("takeLink") { PendingLink.take() }
        Function("reloadWidgets") { WidgetCenter.shared.reloadAllTimelines() }
        Function("watchAppInstalled") { self.watch.installed }
        /// Delivered whenever the Watch is next reachable: {server, key}, or {signedOut: true}.
        Function("updateWatch") { (context: [String: Any]) in
            guard self.watch.installed else { return }
            try WCSession.default.updateApplicationContext(context)
        }
    }
}

final class WatchBridge: NSObject, WCSessionDelegate {
    var onChange: (() -> Void)?
    var installed: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated && WCSession.default.isPaired && WCSession.default.isWatchAppInstalled
    }
    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) { onChange?() }
    func sessionWatchStateDidChange(_ session: WCSession) { onChange?() } // e.g. the Watch app was just installed
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() } // switched to another Watch
}

enum Keychain {
    /// KinwallKit's KeychainConnectionStore query: account "household", the service, and the group.
    static func query(_ service: String, _ shared: Bool) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "household"]
        if shared, let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String, !prefix.isEmpty, !prefix.hasPrefix("$(") {
            q[kSecAttrAccessGroup as String] = prefix + "family.kinwall.shared"
        }
        return q
    }
}
