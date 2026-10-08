import AppIntents
import KinwallKit
import SwiftUI
import WidgetKit

// Siri, Shortcuts and Spotlight's App Shortcuts (docs/WIDGETS-AND-WATCH.md): add to a list, what's
// on today, what's next, start shopping, mark a chore done, and the night screen. They run in the
// app's own process without opening it (the last two and Start shopping open it), with the widgets'
// everyday-access key from the shared Keychain group, so the server's rules for that key apply: it
// can add to lists and tick chores, and a device that belongs to one person can only tick theirs.
// With Chores or Lists turned off in the family's settings, the intents for them answer "Chores
// (Lists) are turned off in Kinwall." and save nothing (requireOn), and "What's on today" skips chores.
//
// Lists, people, today's chores, stores and remembered groceries are entities, so Siri can match
// them in a phrase ("Add to Groceries in Kinwall", "Add milk to Kinwall"); each also answers to its
// plain name, without the emoji.
// App-only: the widget extension's settings keep plain strings (WidgetIntents.swift), and
// OpenIntents.swift holds the intents both share.

func intentClient() throws -> KinwallClient {
    guard let connection = try SharedKeychain.widgetStore.load() else { throw KinwallIntentError.signedOut }
    return KinwallClient(connection)
}

/// The family to ask: nil while the app shows the demo (KinwallKit DemoFamily, where nothing is
/// saved); signed out, the intent says to sign in.
func family() throws -> KinwallClient? { DemoFamily.isOn ? nil : try intentClient() }
private let demoNote = " This is the demo, so nothing is saved."
/// The demo never says "Added": nothing is saved there, and a real family's add must not sound like one.
func demoAdd(_ item: String) -> String { "Kinwall is showing the demo, so \(item) wasn't saved. Sign in to your family in Kinwall to add it." }

enum KinwallIntentError: Error, CustomLocalizedStringResourceConvertible {
    case signedOut, noList, noShoppingList, checklist(String), server(String), demo(String), off(String), said(String)
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut: "Kinwall isn't signed in on this iPhone. Open Kinwall and sign in first."
        case .noList: "Kinwall has no list to add to yet."
        case .noShoppingList: "Kinwall has no shopping list yet."
        case .checklist(let title): "\(title) has a checklist to finish first. Open Kinwall to tick it off."
        case .server(let message): "Kinwall said: \(message)"
        case .demo(let item): "\(demoAdd(item))"
        case .off(let feature): "\(feature) are turned off in Kinwall."
        case .said(let line): "\(line)"
        }
    }
}

/// Stops before anything is saved when the family turned the feature off in Kinwall's settings
/// (Settings → Features). Never in the demo (`kinwall` nil), where everything is on.
func requireOn(_ kinwall: KinwallClient?, _ feature: KeyPath<Features, Bool>, _ name: String) async throws {
    if let kinwall, !(await kinwall.features())[keyPath: feature] { throw KinwallIntentError.off(name) }
}

/// The server's refusal in its own words (a device that belongs to someone else, a 409 checklist).
func explained<T>(_ work: () async throws -> T) async throws -> T {
    do { return try await work() } catch let e as APIError where e != .unreachable && e != .notSaved { throw KinwallIntentError.server(e.message) }
}

/// The household's day, for chores.
private func today(_ kinwall: KinwallClient) async -> String {
    HouseholdDate.key(timezone: try? await kinwall.settings().timezone)
}

/// Groceries (FamilyList.groceries), else the first list.
func defaultList(_ lists: [FamilyList], shopping: Bool = false) -> FamilyList? {
    FamilyList.groceries(in: lists) ?? (shopping ? nil : lists.first { !$0.archived })
}

// MARK: - Entities

struct ListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static let defaultQuery = ListQuery()
    let id: String
    let name: String
    let emoji: String?
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(emoji.map { "\($0) " } ?? "")\(name)", synonyms: ["\(name)"]) }
    init(_ l: FamilyList) { id = l.id; name = l.name; emoji = l.emoji }
}

struct ListQuery: EntityStringQuery {
    func all() async throws -> [ListEntity] {
        let kinwall = try family()
        try await requireOn(kinwall, \.lists, "Lists")
        return try await (kinwall?.lists() ?? DemoFamily.lists).filter { !$0.archived }.map(ListEntity.init)
    }
    func entities(for identifiers: [String]) async throws -> [ListEntity] { try await all().filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [ListEntity] { try await all().filter { $0.name.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [ListEntity] { Array(try await all().prefix(SiriBudget.maxLists)) }
    func defaultResult() async -> ListEntity? { (try? await family()?.lists() ?? DemoFamily.lists).flatMap { defaultList($0) }.map(ListEntity.init) }
}

struct PersonEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Person"
    static let defaultQuery = PersonQuery()
    let id: String
    let name: String
    let avatar: String?
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(avatar.map { "\($0) " } ?? "")\(name)", synonyms: ["\(name)"]) }
    init(_ m: Member) { id = m.id; name = m.name; avatar = m.avatar }
}

struct PersonQuery: EntityStringQuery {
    func all() async throws -> [PersonEntity] { try await (family()?.members() ?? DemoFamily.members).map(PersonEntity.init) }
    func entities(for identifiers: [String]) async throws -> [PersonEntity] { try await all().filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [PersonEntity] { try await all().filter { $0.name.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [PersonEntity] { try await all() }
}

/// One of today's chores, not ticked yet (done, or waiting for a parent's OK).
struct ChoreEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Chore"
    static let defaultQuery = ChoreQuery()
    let id: String
    let title: String
    let emoji: String?
    let memberId: String?
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(emoji.map { "\($0) " } ?? "")\(title)", synonyms: ["\(title)"]) }
    init(_ c: ChoreDay) { id = c.id; title = c.title; emoji = c.emoji; memberId = c.memberId }
}

struct ChoreQuery: EntityStringQuery {
    func all() async throws -> [ChoreEntity] {
        guard let kinwall = try family() else { return DemoFamily.chores.filter { !$0.isTicked }.map(ChoreEntity.init) }
        try await requireOn(kinwall, \.chores, "Chores")
        return try await kinwall.chores(on: today(kinwall)).filter { !$0.isTicked }.map(ChoreEntity.init)
    }
    func entities(for identifiers: [String]) async throws -> [ChoreEntity] { try await all().filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [ChoreEntity] { try await all().filter { $0.title.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [ChoreEntity] { Array(try await all().prefix(SiriBudget.maxChores)) }
}

/// A store the family shops at (the shopping lists' stores).
struct StoreEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Store"
    static let defaultQuery = StoreQuery()
    let id: String // the store's name
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct StoreQuery: EntityStringQuery {
    func all() async throws -> [StoreEntity] {
        guard let kinwall = try family() else { return (DemoFamily.groceries.suggestions?.stores ?? []).map(StoreEntity.init) }
        try await requireOn(kinwall, \.lists, "Lists")
        guard let list = defaultList(try await kinwall.lists(), shopping: true) else { return [] }
        return (try await kinwall.list(list.id).suggestions?.stores ?? []).map(StoreEntity.init)
    }
    func entities(for identifiers: [String]) async throws -> [StoreEntity] { identifiers.map(StoreEntity.init) }
    func entities(matching string: String) async throws -> [StoreEntity] { try await all().filter { $0.id.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [StoreEntity] { Array(try await all().prefix(SiriBudget.maxStores)) }
}

/// A grocery the family has added before (the groceries catalog), so Siri can hear it in one
/// sentence: "Add milk to Kinwall". The most used RememberedItem.siriCap (SiriBudget) of them; anything else
/// goes through "Add to Groceries in Kinwall", which asks for the item.
struct ItemEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Grocery item"
    static let defaultQuery = ItemQuery()
    let id: String // the catalog's title, sent as is so the server finds where it goes
    var name: String { RememberedItem(title: id, uses: 0, lastUsed: nil).plainName }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)", synonyms: ["\(name)"]) }
}

struct ItemQuery: EntityStringQuery {
    func all() async throws -> [RememberedItem] {
        guard let kinwall = try family() else { return DemoFamily.groceries.items.map { RememberedItem(title: $0.title, uses: 1, lastUsed: nil) } }
        try await requireOn(kinwall, \.lists, "Lists")
        return RememberedItem.forSiri(try await kinwall.remembered())
    }
    func entities(for identifiers: [String]) async throws -> [ItemEntity] { identifiers.map(ItemEntity.init) }
    func entities(matching string: String) async throws -> [ItemEntity] { RememberedItem.matching(string, in: try await all()).map { ItemEntity(id: $0.title) } }
    func suggestedEntities() async throws -> [ItemEntity] { try await all().map { ItemEntity(id: $0.title) } }
}

// MARK: - Intents

struct AddToListIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to a list"
    /// Writes to the family's Kinwall: only on an unlocked device (docs/WIDGETS-AND-WATCH.md, Locked iPhone).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let description = IntentDescription("Adds an item to a Kinwall list. Groceries unless you say another list.")
    @Parameter(title: "Item", requestValueDialog: "What should I add?") var item: String
    @Parameter(title: "List") var list: ListEntity?

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$item) to \(\.$list)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let kinwall = try family()
        try await requireOn(kinwall, \.lists, "Lists")
        let target: ListEntity
        if let list { target = list } else {
            guard let fallback = defaultList(try await kinwall?.lists() ?? DemoFamily.lists) else { throw KinwallIntentError.noList }
            target = ListEntity(fallback)
        }
        guard let kinwall else { return .result(dialog: IntentDialog(stringLiteral: demoAdd(item))) }
        // "Added" only once the server hands the item back (KinwallClient.addItem).
        // Not a second copy of what's already there (an open one is left, a ticked one unticked).
        let added = try await explained { try await kinwall.addItem(item, to: target.id, skipExisting: true) }
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: IntentDialog(stringLiteral: added.addedLine(to: target.name)))
    }
}

/// "Add milk to Kinwall": one sentence, always Groceries (an App Shortcut phrase holds one parameter).
struct AddGroceryIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Groceries"
    /// Writes to the family's Kinwall: only on an unlocked device (docs/WIDGETS-AND-WATCH.md, Locked iPhone).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let description = IntentDescription("Adds something the family has bought before to Groceries.")
    @Parameter(title: "Item", requestValueDialog: "What should I add?") var item: ItemEntity

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$item) to Groceries") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let kinwall = try family()
        try await requireOn(kinwall, \.lists, "Lists")
        guard let list = defaultList(try await kinwall?.lists() ?? DemoFamily.lists, shopping: true) else { throw KinwallIntentError.noShoppingList }
        guard let kinwall else { return .result(dialog: IntentDialog(stringLiteral: demoAdd(item.name))) }
        let added = try await explained { try await kinwall.addItem(item.id, to: list.id, skipExisting: true) }
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: IntentDialog(stringLiteral: added.addedLine(to: list.name)))
    }
}

struct WhatsOnTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "What's on today"
    static let description = IntentDescription("Today's events that are still ahead, and how many chores are left (when the family uses chores).")

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let kinwall = try family()
        var board = try await explained { try await kinwall?.board(days: 1) } ?? DemoFamily.board()
        if let kinwall { board = board.respecting(await kinwall.features()) } // no "3 chores left" with chores off
        let summary = TodaySummary(board: board)
        return .result(dialog: IntentDialog(stringLiteral: summary.spoken), view: TodaySnippet(summary: summary))
    }
}

/// What Siri and Shortcuts show under "What's on today".
struct TodaySnippet: View {
    let summary: TodaySummary
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(summary.events.prefix(6)) { e in
                HStack(alignment: .firstTextBaseline) {
                    Text(e.startDate?.formatted(date: .omitted, time: .shortened) ?? "All day").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
                    Text(e.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
            }
            if summary.events.isEmpty { Text("Nothing else on the calendar today.").font(.subheadline).foregroundStyle(.secondary) }
            if summary.choresTotal > 0 {
                Label(summary.choresLeft == 0 ? "All chores done" : "\(summary.choresLeft) of \(summary.choresTotal) chores left", systemImage: "checkmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct WhatsNextIntent: AppIntent {
    static let title: LocalizedStringResource = "What's next"
    static let description = IntentDescription("Tells you what's on now and what's next today.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let board = try await explained { try await family()?.board(days: 1) } ?? DemoFamily.board()
        let (now, next) = board.nowAndNext(at: .now)
        func time(_ e: BoardEvent) -> String { e.startDate?.formatted(date: .omitted, time: .shortened) ?? "all day" }
        var parts: [String] = []
        if let now { parts.append("Now: \(now.title).") }
        if let next {
            var line = "Next: \(next.title) at \(time(next))."
            if let leave = next.leaveDate, leave > .now { line += " Leave by \(leave.formatted(date: .omitted, time: .shortened))." }
            parts.append(line)
        }
        return .result(dialog: IntentDialog(stringLiteral: parts.isEmpty ? "Nothing more on the calendar today." : parts.joined(separator: " ")))
    }
}

struct CompleteChoreIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark a chore done"
    /// Writes to the family's Kinwall: only on an unlocked device (docs/WIDGETS-AND-WATCH.md, Locked iPhone).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let description = IntentDescription("Marks one of today's chores done. For an Anyone chore, say who did it and they get the points.")
    @Parameter(title: "Chore", requestValueDialog: "Which chore?") var chore: ChoreEntity
    @Parameter(title: "Who did it") var person: PersonEntity?

    static var parameterSummary: some ParameterSummary { Summary("Mark \(\.$chore) done for \(\.$person)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let kinwall = try family() else { return .result(dialog: "Marked \(chore.title) done.\(demoNote)") }
        try await requireOn(kinwall, \.chores, "Chores")
        let day = await today(kinwall)
        let current = try await explained { try await kinwall.chores(on: day) }.first { $0.id == chore.id }
        if let checklist = current?.checklist, !checklist.isFinished { throw KinwallIntentError.checklist(chore.title) }
        if current?.completed == true { return .result(dialog: "\(chore.title) is already done.") }
        if current?.pending == true { return .result(dialog: "\(chore.title) is already done. It's waiting for a parent's OK.") }
        // A person's own chore counts for them; an Anyone chore for whoever was named (or nobody in particular).
        let waits = try await explained { try await kinwall.complete(chore: chore.id, on: day, by: chore.memberId ?? person?.id) }
        WidgetCenter.shared.reloadAllTimelines()
        // This key is everyday access, so a chore that needs an OK waits for a parent: no points yet.
        if waits { return .result(dialog: "Marked \(chore.title) done. It's waiting for a parent's OK.") }
        let points = current.map { " \($0.points) points!" } ?? ""
        return .result(dialog: "Marked \(chore.title) done.\(points)")
    }
}

/// Opens shopping mode on Groceries (or the first shopping list), at the store if one's named.
struct StartShoppingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start shopping"
    static let description = IntentDescription("Opens Kinwall's shopping mode on Groceries, optionally at a store.")
    static let openAppWhenRun = true
    @Parameter(title: "Store") var store: StoreEntity?

    static var parameterSummary: some ParameterSummary { Summary("Start shopping at \(\.$store)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        let kinwall = try family()
        try await requireOn(kinwall, \.lists, "Lists")
        guard let list = defaultList(try await kinwall?.lists() ?? DemoFamily.lists, shopping: true) else { throw KinwallIntentError.noShoppingList }
        AppLink.open(AppLink.shop(list: list.id, store: store?.id))
        return .result()
    }
}

// MARK: - Add to Kinwall

/// What Add to Kinwall's content is. Automatic: a link is read by Kinwall; a photo or text asks.
enum ShareKindEnum: String, AppEnum {
    case automatic, recipe, restaurant, book, event
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Kind"
    static let caseDisplayRepresentations: [ShareKindEnum: DisplayRepresentation] = [
        .automatic: "Automatic", .recipe: "Recipe", .restaurant: "Restaurant", .book: "Book", .event: "Event",
    ]
    var kind: Share.Kind? { Share.Kind(rawValue: rawValue) }
}

/// A calendar Add to Kinwall can save an event to: the family's calendars this phone can add to, with
/// the app's own sign-in (KinwallKit Share.calendars), the family's default calendar for new events first.
struct ShareCalendarEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Calendar"
    static let defaultQuery = ShareCalendarQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ShareCalendarQuery: EntityStringQuery {
    func all() async throws -> [ShareCalendarEntity] {
        if DemoFamily.isOn { return [] }
        guard let calendars = await Share.calendars() else { throw KinwallIntentError.said(Share.signInMessage) }
        return calendars.map { ShareCalendarEntity(id: $0.id, name: $0.name) }
    }
    func entities(for identifiers: [String]) async throws -> [ShareCalendarEntity] { try await all().filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [ShareCalendarEntity] { try await all().filter { $0.name.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [ShareCalendarEntity] { try await all() }
}

/// Add to Kinwall (kinwall's docs/using/share-to-kinwall.md): a link, a place, a photo or some text to
/// the family's Kinwall, much as the share sheet does (here the model's guess is taken without asking;
/// Kinwall's answer says where it went) (KinwallKit Share.swift, ShareReader.swift). Signed in
/// as the app is, so it's for a parent's phone; never the widgets' key. Answers with Kinwall's one
/// line and a link that opens the app at what was added, or at what to check (an event, a book to pick).
/// With a Calendar, an event is saved there straight away. Several photos (a menu over pages) are
/// read in order and go as one text, a menu when the model can't tell.
struct AddToKinwallIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Kinwall"
    /// Writes to the family's Kinwall: only on an unlocked device (docs/WIDGETS-AND-WATCH.md, Locked iPhone).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let description = IntentDescription("Adds a recipe or restaurant link, a place, photos of a menu (one or several pages), a book or a flyer, or some text to Kinwall. With Apple Intelligence it tells what a photo or text is; otherwise it asks. An event is added to the Calendar you pick, or without one opens to check first. Returns a link that opens the Kinwall app at it.")
    @Parameter(title: "What it is", default: .automatic) var kind: ShareKindEnum
    @Parameter(title: "Photos") var photo: [IntentFile]? // supportedContentTypes: [.image] is iOS 18+
    @Parameter(title: "Text or link") var text: String?
    @Parameter(title: "Calendar", description: "For an event: the calendar to add it to. Without one, it opens to check first.") var calendar: ShareCalendarEntity?

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$photo) \(\.$text) to Kinwall as \(\.$kind)") { \.$calendar } }

    func perform() async throws -> some IntentResult & ReturnsValue<URL?> & ProvidesDialog {
        if DemoFamily.isOn { throw KinwallIntentError.said("Kinwall is showing the demo, so nothing was added. Sign in to your family in Kinwall first.") }
        let photos = photo ?? []
        if photos.isEmpty, text?.nilIfBlank == nil { throw $text.needsValueError("What should I add?") }
        var kind = kind.kind
        var content = text?.nilIfBlank
        var isbn = false
        var pages = content.map { [$0] } ?? [], links: [String] = []
        if !photos.isEmpty {
            let one = photos.count == 1
            guard let read = await ShareReader.read(count: photos.count, load: { photos[$0].data }, reading: { _ in })
            else { throw KinwallIntentError.said(one ? "Kinwall couldn't open this photo." : "Kinwall couldn't open these photos.") }
            if let found = read.isbn { kind = .book; content = found; isbn = true }
            else if !read.pages.isEmpty { pages = read.pages; links = read.links; content = Share.joinPages(pages) }
            else { throw KinwallIntentError.said(one ? "Kinwall couldn't find any words in this photo." : "Kinwall couldn't find any words in these photos.") }
        }
        // A link goes as it is; an ISBN is a book. Other words: the model's guess (Apple Intelligence),
        // else (several photos) a menu or "What is this?", then the model tidies them when it can.
        if let words = content, !isbn, !photos.isEmpty || Share.onlyLink(words) == nil {
            if kind == nil || kind == .recipe, let guess = await ShareReader.guess(pages) {
                kind = guess.kind
                content = guess.text
            } else {
                if (kind == nil || kind == .recipe), photos.count > 1 { kind = .restaurant }
                if kind == nil || kind == .recipe {
                    kind = try await $kind.requestDisambiguation(among: [.restaurant, .book, .event], dialog: "What is this?").kind
                }
                if let kind { content = await ShareReader.tidied(pages, kind: kind) ?? words }
            }
            // An event goes with the words as read under the model's lines (a street it left out).
            if kind == .event { content = Share.eventText(content, raw: words) }
            if kind == .restaurant { content = content.map { Share.withLinks(links, $0) } }
        }
        guard var request = Share.request(kind: kind, text: content) else { throw KinwallIntentError.said("Nothing to add.") }
        if request.kind == .event, let calendar { request.save = true; request.calendarId = calendar.id }
        switch await Share.send(request) {
        case .failed(let message): throw KinwallIntentError.said(message)
        case .done(let r): return .result(value: Share.appLink(r.link), dialog: IntentDialog(stringLiteral: r.summary))
        }
    }
}

// MARK: - App Shortcuts

struct KinwallShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddToListIntent(), phrases: [
            "Add to \(\.$list) in \(.applicationName)",
            "Add something to \(\.$list) in \(.applicationName)",
            "Add to my \(.applicationName) list",
            "Add something to \(.applicationName)",
            "Add to the grocery list in \(.applicationName)",
            "Add something to the grocery list in \(.applicationName)",
        ], shortTitle: "Add to a list", systemImageName: "cart.badge.plus")
        // Each item counts once per phrase toward Apple's 1,000-phrase limit, so the phrase counts
        // here are KinwallKit's SiriBudget (7 item phrases × 111 items; 20 plain phrases in all).
        // Siri's flexible matching covers small changes in wording ("my" for "the").
        AppShortcut(intent: AddGroceryIntent(), phrases: [
            "Add \(\.$item) to \(.applicationName)",
            "Add \(\.$item) to my \(.applicationName) list",
            "Add \(\.$item) to the grocery list in \(.applicationName)",
            "Add \(\.$item) to my grocery list in \(.applicationName)",
            "Add \(\.$item) to groceries in \(.applicationName)",
            "Add \(\.$item) to the shopping list in \(.applicationName)",
            "Put \(\.$item) on the grocery list in \(.applicationName)",
        ], shortTitle: "Add to Groceries", systemImageName: "basket")
        AppShortcut(intent: WhatsOnTodayIntent(), phrases: [
            "What's on today in \(.applicationName)",
            "What's on \(.applicationName) today",
            "What's happening today in \(.applicationName)",
        ], shortTitle: "What's on today", systemImageName: "calendar")
        AppShortcut(intent: WhatsNextIntent(), phrases: ["What's next on \(.applicationName)", "What's next in \(.applicationName)"],
                    shortTitle: "What's next", systemImageName: "clock")
        AppShortcut(intent: StartShoppingIntent(), phrases: [
            "Start shopping in \(.applicationName)",
            "Start shopping at \(\.$store) in \(.applicationName)",
            "Go shopping with \(.applicationName)",
        ], shortTitle: "Start shopping", systemImageName: "cart")
        AppShortcut(intent: CompleteChoreIntent(), phrases: [
            "Mark \(\.$chore) done in \(.applicationName)",
            "Mark a chore done in \(.applicationName)",
            "Complete a chore in \(.applicationName)",
        ], shortTitle: "Mark a chore done", systemImageName: "checkmark.circle")
        // Add to Kinwall (a photo or text, which Siri can't take by voice) has no phrases: it's a
        // Shortcuts and share action. Vote in a poll and Add an event are Shortcuts actions too.
        AppShortcut(intent: WhatsForDinnerIntent(), phrases: [
            "What's for dinner in \(.applicationName)",
            "What's for dinner tonight in \(.applicationName)",
        ], shortTitle: "What's for dinner", systemImageName: "fork.knife")
        AppShortcut(intent: LogReadingIntent(), phrases: [
            "Log reading in \(.applicationName)",
            "Log my reading in \(.applicationName)",
        ], shortTitle: "Log reading", systemImageName: "book")
        AppShortcut(intent: NightScreenIntent(), phrases: [
            "Start the night screen in \(.applicationName)",
            "Start \(.applicationName) night screen",
            "\(.applicationName) goodnight",
        ], shortTitle: "Night screen", systemImageName: "moon.stars")
    }
}
