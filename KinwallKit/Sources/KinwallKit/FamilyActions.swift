import Foundation

// What Siri's "What's for dinner" and the Shortcuts actions Add an event, Vote in a poll and Log
// reading read and send (native/ios/FamilyIntents.swift). The pure parts are tested in
// FamilyActionsTests.

// MARK: - Meals (GET /api/board `meals`)

/// A planned meal, as the board sends it (the server's Meal; only what Siri reads).
public struct Meal: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    /// The household's YYYY-MM-DD.
    public let date: String
    /// breakfast, lunch, dinner or snack.
    public let slot: String
    public let title: String
    /// recipe, freeform or dining_out (an order night).
    public let mealKind: String
    public let recipeId: String?
    public let restaurantId: String?
    /// dine_in, pickup or delivery.
    public let orderType: String?
    /// HH:MM on the household's clock.
    public let plannedTime: String?
    public init(id: String, date: String, slot: String, title: String, mealKind: String, recipeId: String?, restaurantId: String?, orderType: String?, plannedTime: String?) {
        self.id = id; self.date = date; self.slot = slot; self.title = title; self.mealKind = mealKind
        self.recipeId = recipeId; self.restaurantId = restaurantId; self.orderType = orderType; self.plannedTime = plannedTime
    }
}

public enum Dinner {
    /// When a meal without its own time counts as eaten, for "next today".
    static let slotTimes = ["breakfast": "08:00", "lunch": "12:00", "snack": "15:00", "dinner": "18:00"]
    static let slotNames = ["breakfast": "breakfast", "lunch": "lunch", "snack": "a snack", "dinner": "dinner"]

    /// What Siri says: tonight's dinner (where from and how, on an order night), else the next meal
    /// still ahead today, else that nothing's planned. `now` is HH:MM on the household's clock,
    /// `restaurants` the binder's names by id, `clock` an HH:MM as the phone shows times.
    public static func spoken(meals: [Meal], today: String, now: String, restaurants: [String: String], clock: (String) -> String) -> String {
        let todays = meals.filter { $0.date == today }
        let dinners = todays.filter { $0.slot == "dinner" }
        if !dinners.isEmpty {
            let what = dinners.map { m -> String in
                guard m.mealKind == "dining_out" else { return m.title }
                let place = m.restaurantId.flatMap { restaurants[$0] } ?? m.title
                switch m.orderType {
                case "pickup": return "pickup from \(place)"
                case "delivery": return "delivery from \(place)"
                case "dine_in": return "out at \(place)"
                default: return "from \(place)"
                }
            }
            let at = dinners.compactMap(\.plannedTime).first.map { ", at \(clock($0))" } ?? ""
            return "Dinner tonight is \(what.joined(separator: " and "))\(at)."
        }
        let time = { (m: Meal) in m.plannedTime ?? slotTimes[m.slot] ?? "00:00" }
        let next = todays.filter { time($0) >= now }.min { time($0) < time($1) }
        guard let next else { return "Nothing's planned for dinner tonight." }
        return "Nothing's planned for dinner tonight. Next today: \(next.title) for \(slotNames[next.slot] ?? next.slot)."
    }
}

/// A restaurant in the binder (GET /api/restaurants/{id}); only its name.
public struct Restaurant: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
}

// MARK: - Polls (GET /api/polls, PUT /api/polls/{id}/vote)

public struct PollOption: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    /// Who picked it (member ids).
    public let votes: [String]
}

public struct Poll: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let question: String
    public let status: String
    public let options: [PollOption]
    public var isOpen: Bool { status == "open" }

    /// "Maya voted for Pizza in Friday dinner?"
    public static func votedLine(voter: String, choice: String, question: String) -> String {
        let q = question.trimmingCharacters(in: .whitespaces)
        return "\(voter) voted for \(choice) in \(q)\(q.last.map { ".?!".contains($0) } == true ? "" : ".")"
    }
}

// MARK: - Reading (GET /api/trackers?kind=reading, PATCH /api/trackers/{id})

/// A reading entry: a book or audiobook on someone's shelf.
public struct ReadingEntry: Codable, Identifiable, Hashable, Sendable {
    public struct Progress: Codable, Hashable, Sendable {
        public let format: String?
        public let status: String?
        public let pagesRead: Int?
        public let totalPages: Int?
        public let minutesListened: Int?
        public let totalMinutes: Int?
    }
    public let id: String
    /// nil: the whole family's, or someone since removed.
    public let memberId: String?
    public let title: String?
    public let data: Progress
    public var isAudiobook: Bool { data.format == "audiobook" }
    public var isReading: Bool { (data.status ?? "reading") == "reading" }

    /// After `amount` more pages (minutes for an audiobook): what to send, never past the end, and
    /// finished at the last page, as the app's Log pages sheet does (the server logs the day).
    public func logged(_ amount: Int) -> ReadingLog {
        let was = (isAudiobook ? data.minutesListened : data.pagesRead) ?? 0
        let total = isAudiobook ? data.totalMinutes : data.totalPages
        let now = min(total ?? Int.max, was + max(0, amount))
        let finished = total.map { now >= $0 } ?? false
        return ReadingLog(patch: ReadingPatch(pagesRead: isAudiobook ? nil : now, minutesListened: isAudiobook ? now : nil, status: finished ? "finished" : nil),
                          title: title ?? "the book", audiobook: isAudiobook, added: now - was, at: now, total: total, finished: finished)
    }
}

/// PATCH /api/trackers/{id}'s `data`: only what changed.
public struct ReadingPatch: Codable, Hashable, Sendable {
    public var pagesRead: Int?
    public var minutesListened: Int?
    public var status: String?
    struct Body: Encodable { let data: ReadingPatch }
}

public struct ReadingLog: Hashable, Sendable {
    public let patch: ReadingPatch
    let title: String, audiobook: Bool, added: Int, at: Int, total: Int?, finished: Bool

    /// What Siri says once it's saved; `reader`: whose book, when known.
    public func line(for reader: String?) -> String {
        let unit = audiobook ? (added == 1 ? "minute" : "minutes") : (added == 1 ? "page" : "pages")
        let first = "Logged \(added) \(unit) of \(title)\(reader.map { " for \($0)" } ?? "")."
        if finished { return first + (audiobook ? " That's the end, so it's marked finished!" : " That's the last page, so it's marked finished!") }
        guard !audiobook else { return first }
        return first + " Now on page \(at)\(total.map { " of \($0)" } ?? "")."
    }
}

// MARK: - Client

extension KinwallClient {
    public func restaurant(_ id: String) async throws -> Restaurant { try await send("GET", "api/restaurants/\(id)") }

    /// Open polls first, then newest (404 while the family has polls off).
    public func polls() async throws -> [Poll] { try await send("GET", "api/polls", query: [URLQueryItem(name: "status", value: "open")]) }
    /// A member's vote; a member's own device votes only for them (the server says so with a 403).
    public func vote(poll: String, option: String, member: String) async throws {
        struct Vote: Encodable { let memberId: String; let optionId: String }
        try await sendIgnoringBody("PUT", "api/polls/\(poll)/vote", body: Vote(memberId: member, optionId: option))
    }

    public func readingEntries() async throws -> [ReadingEntry] { try await send("GET", "api/trackers", query: [URLQueryItem(name: "kind", value: "reading")]) }
    public func readingEntry(_ id: String) async throws -> ReadingEntry { try await send("GET", "api/trackers/\(id)") }
    public func logReading(_ entry: String, _ patch: ReadingPatch) async throws {
        try await sendIgnoringBody("PATCH", "api/trackers/\(entry)", body: ReadingPatch.Body(data: patch))
    }

    /// The calendars this key can add an event to, the family's default for new events first (Share.addable).
    public func addableCalendars() async throws -> [Share.FamilyCalendar] { Share.addable(try await send("GET", "api/calendars")) }
    /// A timed event; nil `calendarId` is the family's default calendar for new events.
    public func addEvent(title: String, start: Date, end: Date, calendarId: String?) async throws {
        struct NewEvent: Encodable { let title: String; let start: String; let end: String; let allDay = false; let calendarId: String? }
        let iso = ISO8601DateFormatter()
        try await sendIgnoringBody("POST", "api/events", body: NewEvent(title: title, start: iso.string(from: start), end: iso.string(from: end), calendarId: calendarId))
    }
}
