// iOS 27's Reminders app schema (docs/WIDGETS-AND-WATCH.md, Siri): with it, Apple Intelligence's
// Siri hears a whole sentence like "Add garlic to the grocery list in Kinwall" and hands us the
// item as free text, so it works for things the family has never added. App Shortcut phrases
// (SiriIntents.swift) can only hold entities, so there an item has to be in the groceries catalog.
//
// A Kinwall list is a reminders list and an item a reminder. The schema fixes every parameter and
// property; Kinwall items have none of flags, tags, URLs, images, sections, location triggers or
// recurrence, so those are accepted and left out rather than guessed.
//
// The iOS 27 SDK (Xcode 27, Swift 6.4) has the schema; older Xcodes build the app without it.
#if compiler(>=6.4)
import AppIntents
import CoreLocation
import GeoToolbox
import KinwallKit
import WidgetKit

@available(iOS 27.0, *)
@AppEnum(schema: .reminders.listType)
enum KinwallListType: String {
    case standard
    static let caseDisplayRepresentations: [KinwallListType: DisplayRepresentation] = [.standard: "List"]
}

@available(iOS 27.0, *)
@AppEntity(schema: .reminders.list)
struct KinwallReminderList {
    static let defaultQuery = KinwallReminderListQuery()
    var id: String
    var name: String
    var type: KinwallListType
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(_ l: FamilyList) { id = l.id; name = l.name; type = .standard }
    init() { id = ""; name = ""; type = .standard } // for the section placeholder the schema requires
}

@available(iOS 27.0, *)
struct KinwallReminderListQuery: EntityStringQuery {
    func lists() async throws -> [FamilyList] { try await (family()?.lists() ?? DemoFamily.lists).filter { !$0.archived } }
    func entities(for identifiers: [String]) async throws -> [KinwallReminderList] { try await lists().filter { identifiers.contains($0.id) }.map(KinwallReminderList.init) }
    // "the grocery list" or "groceries" both find Groceries: matched on the name without the emoji either way.
    func entities(matching string: String) async throws -> [KinwallReminderList] {
        let wanted = RememberedItem(title: string, uses: 0, lastUsed: nil).plainName
        return try await lists().filter { list in
            let name = RememberedItem(title: list.name, uses: 0, lastUsed: nil).plainName
            return name.localizedCaseInsensitiveContains(wanted) || wanted.localizedCaseInsensitiveContains(name)
        }.map(KinwallReminderList.init)
    }
    func suggestedEntities() async throws -> [KinwallReminderList] { try await lists().map(KinwallReminderList.init) }
}

@available(iOS 27.0, *)
@AppEnum(schema: .reminders.locationTriggerEvent)
enum KinwallLocationTriggerEvent: String {
    case arrive, depart
    static let caseDisplayRepresentations: [KinwallLocationTriggerEvent: DisplayRepresentation] = [.arrive: "Arriving", .depart: "Leaving"]
}

/// Never produced: Kinwall items have no location trigger. The schema requires the shape.
@available(iOS 27.0, *)
@AppEntity(schema: .reminders.locationTrigger)
struct KinwallLocationTrigger: TransientAppEntity {
    var place: PlaceDescriptor
    var event: KinwallLocationTriggerEvent
    var displayRepresentation: DisplayRepresentation { "Location" }
    init() { place = PlaceDescriptor(representations: [.coordinate(CLLocationCoordinate2D())], commonName: nil); event = .arrive }
}

/// Never produced: Kinwall lists have no sections. The schema requires the shape.
@available(iOS 27.0, *)
@AppEntity(schema: .reminders.section)
struct KinwallReminderSection: TransientAppEntity {
    var name: String
    var list: KinwallReminderList
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    init() { name = ""; list = KinwallReminderList() }
}

/// An item on a Kinwall list. Its id is "listId/itemId", so the query can find it again.
@available(iOS 27.0, *)
@AppEntity(schema: .reminders.reminder)
struct KinwallReminder {
    static let defaultQuery = KinwallReminderQuery()
    var id: String
    var title: String
    var list: KinwallReminderList
    var dueDate: DateComponents?
    var completionDate: Date?
    var creationDate: Date?
    var isCompleted: Bool
    var isFlagged: Bool?
    var recurrence: Calendar.RecurrenceRule?
    var locationTrigger: KinwallLocationTrigger?
    var note: String?
    var tags: Set<String>
    var urls: [URL]
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    init(id: String, title: String, list: KinwallReminderList, done: Bool, note: String?) {
        self.id = id; self.title = title; self.list = list; isCompleted = done; self.note = note
        dueDate = nil; completionDate = nil; creationDate = nil; isFlagged = nil; recurrence = nil; locationTrigger = nil; tags = []; urls = []
    }
    init(_ item: ListItem, in list: KinwallReminderList) {
        self.init(id: "\(list.id)/\(item.id)", title: item.title, list: list, done: item.done, note: item.notes)
    }
}

@available(iOS 27.0, *)
struct KinwallReminderQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [KinwallReminder] {
        guard let kinwall = try family() else { return [] }
        var found: [KinwallReminder] = []
        for listId in Set(identifiers.compactMap { $0.split(separator: "/").first.map(String.init) }) {
            let detail = try await kinwall.list(listId)
            let list = KinwallReminderList(detail.list)
            found += detail.items.map { KinwallReminder($0, in: list) }.filter { identifiers.contains($0.id) }
        }
        return found
    }
}

/// "Add garlic to the grocery list in Kinwall": Groceries unless another list is named.
@available(iOS 27.0, *)
@AppIntent(schema: .reminders.createReminder)
struct CreateKinwallReminderIntent {
    /// Writes to the family's Kinwall: only on an unlocked device (docs/WIDGETS-AND-WATCH.md, Locked iPhone).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    var title: String
    var list: KinwallReminderList?
    var note: AttributedString?
    var isFlagged: Bool?
    var images: [IntentFile]
    var tags: Set<String>
    var urls: [URL]
    var dueDate: DateComponents?
    var recurrence: Calendar.RecurrenceRule?
    var locationTrigger: KinwallLocationTrigger?
    var section: KinwallReminderSection?

    func perform() async throws -> some ReturnsValue<KinwallReminder> & ProvidesDialog {
        let kinwall = try family()
        try await requireOn(kinwall, \.lists, "Lists") // like Add to a list: nothing saved with Lists off
        let target: KinwallReminderList
        if let list { target = list } else {
            guard let fallback = defaultList(try await kinwall?.lists() ?? DemoFamily.lists) else { throw KinwallIntentError.noList }
            target = KinwallReminderList(fallback)
        }
        // Siri says it's added once this returns, so the demo throws and a real add waits for the item.
        guard let kinwall else { throw KinwallIntentError.demo(title) }
        // "Add water and garlic" with garlic already there: one of each, and Siri says which.
        let item = try await explained { try await kinwall.addItem(title, to: target.id, skipExisting: true) }
        WidgetCenter.shared.reloadAllTimelines()
        return .result(value: KinwallReminder(item, in: target), dialog: IntentDialog(stringLiteral: item.addedLine(to: target.name)))
    }
}
#endif
