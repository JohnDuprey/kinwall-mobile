import AppIntents
import Foundation
import KinwallKit
#if canImport(KinwallNative)
internal import KinwallNative // the app: PendingLink hands the link to the web app
#endif

// Intents that open the app somewhere: shopping mode, a list, the night screen. Compiled into the
// app and the widget extension (plugins/withKinwallNative.js), because the Controls
// (targets/widgets/Controls.swift) live in the extension and iOS runs an openAppWhenRun intent in
// the app, which needs the type too. Siri's Start shopping (with a store) is in SiriIntents.swift.

/// The app's own links (src/links.ts routeFor turns them into the web app's routes).
enum AppLink {
    static func shop(list: String, store: String?) -> String {
        var c = URLComponents(string: "family.kinwall.app:/open")!
        c.queryItems = [URLQueryItem(name: "to", value: "lists/\(list)/shop")] + (store.map { [URLQueryItem(name: "store", value: $0)] } ?? [])
        return c.string!
    }
    static func list(_ id: String) -> String { "family.kinwall.app:/open?to=lists&list=\(id)" }
    static let night = "family.kinwall.app:/open?to=night"

    /// In the app: queue the link for the web app (modules/kinwall-native PendingLink). The widget
    /// extension never runs these (openAppWhenRun), so it's a no-op there.
    static func open(_ link: String) {
        #if canImport(KinwallNative)
        PendingLink.open(link)
        #endif
    }
}

/// The shopping list Siri and the controls mean (FamilyList.groceries).
func groceries(_ kinwall: KinwallClient) async throws -> FamilyList? {
    FamilyList.groceries(in: try await kinwall.lists())
}

private func openClient() -> KinwallClient? { (try? SharedKeychain.widgetStore.load()).map { KinwallClient($0) } }
/// Groceries' id: the family's, or the demo's.
private func groceriesId() async -> String? {
    if DemoFamily.isOn { return DemoFamily.groceries.list.id }
    guard let kinwall = openClient() else { return nil }
    return try? await groceries(kinwall)?.id
}

/// Lists turned off in the family's settings: the controls then just open the app. On when it
/// can't tell (signed out, offline, the demo).
private func listsOn() async -> Bool {
    guard !DemoFamily.isOn, let kinwall = openClient() else { return true }
    return await kinwall.features().lists
}

/// "Start the night screen": the app shows the dim night clock until a tap, as the header's 🌙 button does.
struct NightScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Start the night screen"
    static let description = IntentDescription("Opens Kinwall on the dim night clock, until a tap.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        AppLink.open(AppLink.night)
        return .result()
    }
}

/// Control Center's Start shopping: shopping mode on Groceries (the web app asks which store).
struct ShopGroceriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Shop Groceries"
    static let description = IntentDescription("Opens Kinwall's shopping mode on Groceries.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        guard await listsOn() else { return .result() }
        // Signed out or offline: the app opens on its Lists (or sign-in) instead.
        if let id = await groceriesId() { AppLink.open(AppLink.shop(list: id, store: nil)) }
        else { AppLink.open("family.kinwall.app:/open?to=lists") }
        return .result()
    }
}

/// Control Center's Add to Groceries: opens Groceries, where the add field is. Titled Open Groceries
/// so Shortcuts doesn't list two "Add to Groceries" actions (Siri's AddGroceryIntent adds the item).
struct OpenGroceriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Groceries"
    static let description = IntentDescription("Opens Groceries in Kinwall to add something.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        guard await listsOn() else { return .result() }
        if let id = await groceriesId() { AppLink.open(AppLink.list(id)) }
        else { AppLink.open("family.kinwall.app:/open?to=lists") }
        return .result()
    }
}
