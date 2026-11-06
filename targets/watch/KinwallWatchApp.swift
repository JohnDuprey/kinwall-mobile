import SwiftUI
import WatchConnectivity
import KinwallKit
import WidgetKit
import UserNotifications

/// The Watch app (M4, docs/WIDGETS-AND-WATCH.md): Today, My chores, Check-in, Take now and Lists, plus haptic
/// transition warnings (Transitions.swift). Its key comes from the
/// iPhone app over WatchConnectivity and is kept in the Watch's own Keychain.
@main
struct KinwallWatchApp: App {
    @State private var link = PhoneLink()
    @State private var destination = WatchDestination.today

    var body: some Scene {
        WindowGroup {
            Group {
                if let connection = link.connection {
                    TabView(selection: $destination) {
                        TodayView(client: KinwallClient(connection)).tag(WatchDestination.today)
                        ChoresView(client: KinwallClient(connection)).tag(WatchDestination.chores)
                        CheckInView(client: KinwallClient(connection)).tag(WatchDestination.checkIn)
                        MedsView(client: KinwallClient(connection)).tag(WatchDestination.medicines)
                        ListsView(client: KinwallClient(connection)).tag(WatchDestination.lists)
                    }
                    .tabViewStyle(.verticalPage)
                    .id(connection.key) // a new household (or key) starts fresh
                    .task { await Transitions.refresh(KinwallClient(connection)); Transitions.scheduleBackgroundRefresh() }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "iphone").font(.title2).foregroundStyle(.secondary)
                        Text("Open Kinwall on your iPhone to connect this Watch.").font(.footnote).multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .onOpenURL { url in
                if let next = WatchDestination(url: url) { destination = next }
            }
        }
        // Transition warnings (Transitions.swift) are rescheduled here too, while the app is closed.
        .backgroundTask(.appRefresh(Transitions.refreshTask)) {
            if let connection = try? SharedKeychain.widgetStore.load() { await Transitions.refresh(KinwallClient(connection)) }
            await Transitions.scheduleBackgroundRefresh()
        }
    }

    init() { UNUserNotificationCenter.current().delegate = NotificationHandler.shared }
}

/// Receives the Watch's key from the iPhone app (src/sharedKey.ts, through modules/kinwall-native).
@MainActor @Observable
final class PhoneLink: NSObject, WCSessionDelegate {
    private(set) var connection: Connection?
    private let store = SharedKeychain.widgetStore // shared with the complications

    override init() {
        super.init()
        connection = try? store.load()
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// What the iPhone sent, as plain values that can cross to the main actor.
    private struct Update: Sendable { let server: String?; let key: String?; let signedOut: Bool }
    private nonisolated static func update(_ context: [String: Any]) -> Update? {
        context.isEmpty ? nil : Update(server: context["server"] as? String, key: context["key"] as? String, signedOut: context["signedOut"] as? Bool == true)
    }

    private func apply(_ u: Update) {
        if u.signedOut {
            try? store.clear(); connection = nil
            WidgetCenter.shared.reloadAllTimelines()
        } else if let server = u.server.flatMap(URL.init(string:)), let key = u.key {
            let next = Connection(baseURL: server, key: key)
            try? store.save(next); connection = next
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard let u = Self.update(session.receivedApplicationContext) else { return }
        Task { @MainActor in apply(u) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let u = Self.update(context) else { return }
        Task { @MainActor in apply(u) }
    }
}
