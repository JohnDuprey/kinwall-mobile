import AppIntents
import KinwallKit
import WidgetKit

// Siri's "What's for dinner" and the Shortcuts actions Add an event, Vote in a poll and Log reading
// (docs/WIDGETS-AND-WATCH.md). Like SiriIntents.swift they run in the app's process with the widgets'
// everyday-access key, so the server's rules for that key apply: a device that belongs to one
// person votes and logs reading only for them. Add an event uses the app's own sign-in when the
// phone has one (a grown-up's phone can add to every calendar), else that key (the calendars walls
// and kids may add to). In the demo they read the demo family and save nothing.

private let demoNothingSaved = "Kinwall is showing the demo, so nothing was saved. Sign in to your family in Kinwall first."

/// Reading's switch reads "Reading is", not requireOn's "… are turned off".
private func requireReading(_ kinwall: KinwallClient) async throws {
    if !(await kinwall.features()).trackersReading { throw KinwallIntentError.said("Reading is turned off in Kinwall.") }
}

/// This device's person (a kid's own device, or a grown-up's phone that knows whose it is); nil on a
/// shared device or when it can't be asked.
private func devicePerson(_ kinwall: KinwallClient) async -> String? { try? await kinwall.me().person }

// MARK: - What's for dinner

struct WhatsForDinnerIntent: AppIntent {
    static let title: LocalizedStringResource = "What's for dinner"
    static let description = IntentDescription("Tells you tonight's planned dinner, with the restaurant and whether it's pickup or delivery on an order night. With no dinner planned, it says what's next today.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let kinwall = try family()
        let settings = try? await kinwall?.settings()
        if settings?.on.meals == false { throw KinwallIntentError.off("Meals") }
        let board = try await explained { try await kinwall?.board(days: 1) } ?? DemoFamily.board()
        guard let meals = board.meals else { return .result(dialog: "Update Kinwall to ask what's for dinner.") }
        var restaurants: [String: String] = [:]
        if let kinwall {
            for id in Set(meals.filter { $0.date == board.today && $0.slot == "dinner" }.compactMap(\.restaurantId)) {
                restaurants[id] = try? await kinwall.restaurant(id).name // one since deleted goes by the meal's name
            }
        }
        let tz = settings?.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        let hm = DateFormatter()
        hm.locale = Locale(identifier: "en_US_POSIX")
        hm.dateFormat = "HH:mm"
        hm.timeZone = tz
        let now = hm.string(from: .now)
        hm.timeZone = Share.utc
        let line = Dinner.spoken(meals: meals, today: board.today, now: now, restaurants: restaurants) { time in
            hm.date(from: time)?.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: Share.utc)) ?? time
        }
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}

// MARK: - Add an event

/// The app's own sign-in (a grown-up's phone: every calendar), else the widgets' key.
private func eventsClient() async throws -> KinwallClient {
    if let signedIn = try? await AppSignIn.credential() { return KinwallClient(signedIn) }
    return try intentClient()
}

/// One of the family's calendars this phone can add an event to, the default for new events first.
struct CalendarEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Calendar"
    static let defaultQuery = CalendarQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct CalendarQuery: EntityStringQuery {
    func all() async throws -> [CalendarEntity] {
        if DemoFamily.isOn { return [] }
        let kinwall = try await eventsClient()
        return try await explained { try await kinwall.addableCalendars() }.map { CalendarEntity(id: $0.id, name: $0.name) }
    }
    func entities(for identifiers: [String]) async throws -> [CalendarEntity] { try await all().filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [CalendarEntity] { try await all().filter { $0.name.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [CalendarEntity] { try await all() }
    func defaultResult() async -> CalendarEntity? { try? await all().first }
}

struct AddEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Add an event"
    /// Writes to the family's Kinwall: only on an unlocked device (docs/WIDGETS-AND-WATCH.md, Locked iPhone).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let description = IntentDescription("Adds an event to the family's Kinwall calendar, on the family's default calendar unless you pick another. It lasts the family's usual event length (set in Kinwall's settings) unless you say when it ends.")
    @Parameter(title: "Title", requestValueDialog: "What's the event called?") var name: String
    @Parameter(title: "Starts", kind: .dateTime, requestValueDialog: "When does it start?") var start: Date
    @Parameter(title: "Ends", kind: .dateTime) var end: Date?
    @Parameter(title: "Calendar") var calendar: CalendarEntity?

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$name) at \(\.$start)") { \.$end; \.$calendar } }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if DemoFamily.isOn { throw KinwallIntentError.said(demoNothingSaved) }
        let kinwall = try await eventsClient()
        var target = calendar
        if target == nil { target = try await CalendarQuery().all().first }
        guard let target else {
            throw KinwallIntentError.said("This phone can't add events to the family's calendars. Open Kinwall and sign in as a grown-up first.")
        }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { throw $name.needsValueError("What's the event called?") }
        // No end (or one before the start): the family's usual event length, an hour on older servers.
        let finish: Date
        if let end, end > start { finish = end } else {
            finish = start.addingTimeInterval(Double(((try? await kinwall.settings())?.eventMinutes ?? 60) * 60))
        }
        try await explained { try await kinwall.addEvent(title: title, start: start, end: finish, calendarId: target.id) }
        WidgetCenter.shared.reloadAllTimelines()
        let when = start.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute())
        return .result(dialog: IntentDialog(stringLiteral: "Added \(title) to \(target.name) on \(when)."))
    }
}

// MARK: - Vote in a poll

/// An open family poll.
struct PollEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Poll"
    static let defaultQuery = PollQuery()
    let id: String
    let question: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(question)") }
}

/// The family's open polls (none in the demo; polls turned off says so).
private func openPolls() async throws -> [Poll] {
    guard let kinwall = try family() else { return [] }
    try await requireOn(kinwall, \.polls, "Polls")
    return try await explained { try await kinwall.polls() }.filter(\.isOpen)
}

struct PollQuery: EntityStringQuery {
    func all() async throws -> [PollEntity] { try await openPolls().map { PollEntity(id: $0.id, question: $0.question) } }
    func entities(for identifiers: [String]) async throws -> [PollEntity] { try await all().filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [PollEntity] { try await all().filter { $0.question.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [PollEntity] { try await all() }
}

/// One of a poll's choices; its id is the poll's and the choice's.
struct PollChoiceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Poll choice"
    static let defaultQuery = PollChoiceQuery()
    let id: String
    let pollId: String
    let label: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(label)") }
    init(poll: String, option: PollOption) { id = "\(poll)|\(option.id)"; pollId = poll; label = option.label }
    var optionId: String { String(id.split(separator: "|", maxSplits: 1).last ?? "") }
}

struct PollChoiceQuery: EntityStringQuery {
    /// The poll picked in Vote in a poll, so only its choices are offered.
    @IntentParameterDependency<VoteInPollIntent>(\.$poll) var vote

    func all() async throws -> [PollChoiceEntity] {
        try await openPolls().filter { vote == nil || $0.id == vote?.poll.id }.flatMap { p in p.options.map { PollChoiceEntity(poll: p.id, option: $0) } }
    }
    func entities(for identifiers: [String]) async throws -> [PollChoiceEntity] {
        try await openPolls().flatMap { p in p.options.map { PollChoiceEntity(poll: p.id, option: $0) } }.filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [PollChoiceEntity] { try await all().filter { $0.label.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [PollChoiceEntity] { try await all() }
}

struct VoteInPollIntent: AppIntent {
    static let title: LocalizedStringResource = "Vote in a poll"
    /// Writes to the family's Kinwall: only on an unlocked device (docs/WIDGETS-AND-WATCH.md, Locked iPhone).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let description = IntentDescription("Votes in one of the family's open polls in Kinwall. A phone that belongs to someone votes for them; on a shared one, say who's voting. Voting again changes the vote.")
    @Parameter(title: "Poll", requestValueDialog: "Which poll?") var poll: PollEntity
    @Parameter(title: "Choice", requestValueDialog: "What's your pick?") var choice: PollChoiceEntity
    @Parameter(title: "Who's voting") var voter: PersonEntity?

    static var parameterSummary: some ParameterSummary { Summary("Vote for \(\.$choice) in \(\.$poll)") { \.$voter } }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let kinwall = try family() else { throw KinwallIntentError.said(demoNothingSaved) }
        try await requireOn(kinwall, \.polls, "Polls")
        if choice.pollId != poll.id { throw $choice.needsValueError("What's your pick in \(poll.question)?") }
        let member: String, name: String?
        if let owner = await devicePerson(kinwall) {
            member = owner
            name = (try? await kinwall.members())?.first { $0.id == owner }?.name
        } else if let voter {
            member = voter.id; name = voter.name
        } else {
            throw $voter.needsValueError("Who's voting?")
        }
        try await explained { try await kinwall.vote(poll: poll.id, option: choice.optionId, member: member) }
        let line = name.map { Poll.votedLine(voter: $0, choice: choice.label, question: poll.question) } ?? "Your vote is in: \(choice.label)."
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}

// MARK: - Log reading

/// A book someone's reading (their reading shelf in Kinwall). On a device that belongs to someone,
/// only theirs.
struct BookEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Book"
    static let defaultQuery = BookQuery()
    let id: String
    let title: String
    let reader: String?
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: reader.map { "\($0)" }, synonyms: ["\(title)"])
    }
}

struct BookQuery: EntityStringQuery {
    func all() async throws -> [BookEntity] {
        guard let kinwall = try family() else { return [] }
        try await requireReading(kinwall)
        let entries = try await explained { try await kinwall.readingEntries() }.filter(\.isReading)
        let person = await devicePerson(kinwall)
        let names = Dictionary(((try? await kinwall.members()) ?? []).map { ($0.id, $0.name) }) { a, _ in a }
        return entries.filter { person == nil || $0.memberId == person }
            .map { BookEntity(id: $0.id, title: $0.title ?? "Untitled", reader: $0.memberId.flatMap { names[$0] }) }
    }
    func entities(for identifiers: [String]) async throws -> [BookEntity] { try await all().filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [BookEntity] { try await all().filter { $0.title.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [BookEntity] { try await all() }
}

struct LogReadingIntent: AppIntent {
    static let title: LocalizedStringResource = "Log reading"
    /// Writes to the family's Kinwall: only on an unlocked device (docs/WIDGETS-AND-WATCH.md, Locked iPhone).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let description = IntentDescription("Logs pages read (minutes for an audiobook) for a book on someone's reading shelf in Kinwall. At the last page, the book is marked finished.")
    @Parameter(title: "Book", requestValueDialog: "Which book?") var book: BookEntity
    @Parameter(title: "Pages or minutes", inclusiveRange: (1, 2000)) var amount: Int?

    static var parameterSummary: some ParameterSummary { Summary("Log reading for \(\.$book)") { \.$amount } }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let kinwall = try family() else { throw KinwallIntentError.said(demoNothingSaved) }
        try await requireReading(kinwall)
        let entry = try await explained { try await kinwall.readingEntry(book.id) }
        guard let amount, amount > 0 else {
            throw $amount.needsValueError(entry.isAudiobook ? "How many minutes did you listen?" : "How many pages did you read?")
        }
        let log = entry.logged(amount)
        try await explained { try await kinwall.logReading(entry.id, log.patch) }
        return .result(dialog: IntentDialog(stringLiteral: log.line(for: book.reader)))
    }
}
