import SwiftUI
import WidgetKit
import AppIntents
import KinwallKit

// The App Intents behind the interactive widgets (docs/WIDGETS-AND-WATCH.md): their settings
// (whose chores, which list), the people and lists to pick from, and the tick-off actions.
// Only in the widget extension. Compiled into the app as well, the app's copy of ChoresScope
// shadowed this one and the widget read "One person" back as the whole family.

func widgetClient() throws -> KinwallClient {
    guard let connection = try SharedKeychain.widgetStore.load() else { throw WidgetError.signedOut }
    return KinwallClient(connection)
}
enum WidgetError: Error, CustomLocalizedStringResourceConvertible {
    case signedOut
    var localizedStringResource: LocalizedStringResource { "Open Kinwall to sign in first." }
}

// MARK: - Entities for configuration

/// A person on a Chores widget. Its settings use only strings and switches: a custom AppEntity
/// or AppEnum saved in a widget's settings came back empty (the whole family) when read.
struct MemberEntity {
    let id: String
    let name: String
    let avatar: String?
    /// Stands in for "Anyone chores" in the widget's header and credit logic.
    static let anyone = MemberEntity(id: "__anyone", name: "Anyone", avatar: "🌟")
    var isAnyone: Bool { id == Self.anyone.id }
}
/// The people to pick from on a Chores widget, saved by id, after "Everyone" (saved as is, so
/// the default reads well before the list loads).
struct MemberOptions: DynamicOptionsProvider {
    static let everyone = "Everyone"
    func results() async throws -> ItemCollection<String> {
        let members = Demo.isOn ? Demo.members : ((try? await widgetClient().members()) ?? [])
        return ItemCollection {
            ItemSection(items: [IntentItem(Self.everyone, title: "Everyone")])
            ItemSection(items: members.map { IntentItem($0.id, title: "\($0.avatar.map { "\($0) " } ?? "")\($0.name)") })
        }
    }
    func defaultResult() async -> String? { Self.everyone }
}

/// The lists to pick from on a List widget, saved by id (a plain string, like the Chores widget's person).
struct ListOptions: DynamicOptionsProvider {
    func results() async throws -> ItemCollection<String> {
        let lists = Demo.isOn ? [Demo.groceries.list] : try await widgetClient().lists().filter { !$0.archived }
        return ItemCollection { ItemSection(items: lists.map { IntentItem($0.id, title: "\($0.emoji.map { "\($0) " } ?? "")\($0.name)") }) }
    }
}

struct ChoresConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Whose chores"
    static let description = IntentDescription("Show everyone's chores, one person's, or only Anyone chores. Anyone chores ticked on a person's widget count for them.")
    @Parameter(title: "Person", optionsProvider: MemberOptions()) var member: String?
    @Parameter(title: "Include Anyone chores", default: true) var includeAnyone: Bool
    @Parameter(title: "Only Anyone chores", default: false) var onlyAnyone: Bool

    // Only Anyone chores makes the person and the Anyone toggle moot, so they hide.
    static var parameterSummary: some ParameterSummary {
        When(\.$onlyAnyone, .equalTo, true) {
            Summary("Chores") { \.$onlyAnyone }
        } otherwise: {
            Summary("Chores for \(\.$member)") { \.$includeAnyone; \.$onlyAnyone }
        }
    }
}

struct ListConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Which list"
    static let description = IntentDescription("Tick items off a list, like Groceries.")
    @Parameter(title: "List", optionsProvider: ListOptions()) var list: String?
}

// MARK: - Actions

struct ToggleChoreIntent: AppIntent {
    static let title: LocalizedStringResource = "Tick off a chore"
    /// Writes to the family's Kinwall: only on an unlocked device (docs/WIDGETS-AND-WATCH.md, Locked iPhone).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let isDiscoverable = false
    @Parameter(title: "Chore") var choreId: String
    @Parameter(title: "Date") var date: String
    @Parameter(title: "Done") var done: Bool
    @Parameter(title: "Credit") var creditTo: String?
    init() {}
    init(choreId: String, date: String, done: Bool, creditTo: String?) {
        self.choreId = choreId; self.date = date; self.done = done; self.creditTo = creditTo
    }
    func perform() async throws -> some IntentResult {
        let client = try widgetClient()
        if done { try await client.complete(chore: choreId, on: date, by: creditTo) } else { try await client.uncomplete(chore: choreId, on: date) }
        return .result()
    }
}

struct ToggleItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Tick off a list item"
    /// Writes to the family's Kinwall: only on an unlocked device (docs/WIDGETS-AND-WATCH.md, Locked iPhone).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let isDiscoverable = false
    @Parameter(title: "List") var listId: String
    @Parameter(title: "Item") var itemId: String
    @Parameter(title: "Done") var done: Bool
    init() {}
    init(listId: String, itemId: String, done: Bool) { self.listId = listId; self.itemId = itemId; self.done = done }
    func perform() async throws -> some IntentResult {
        try await widgetClient().setDone(done, item: itemId, in: listId)
        return .result()
    }
}

