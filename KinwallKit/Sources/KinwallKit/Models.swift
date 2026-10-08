import Foundation

// The subset of Kinwall's REST shapes the apps use (see the server's /openapi.json).
// Fields the apps don't read are left out; unknown fields are ignored when decoding.

public struct Member: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let color: String
    public let avatar: String?
    public let pointsToday: Int
    public let pointsWeek: Int
    public let balance: Int
    /// Warnings before their events (the Watch plays them); nil when an admin hasn't set any.
    public var transitionReminders: TransitionReminders? = nil
}

public struct Settings: Codable, Hashable, Sendable {
    public let familyName: String
    public let timezone: String?
    public let weekStart: Int
    public let colorScheme: String?
    /// The family's feature switches; nil from servers older than them (everything on).
    public var features: Features? = nil
    /// Rewards (spending points); nil from older servers (on).
    public var rewardsEnabled: Bool? = nil
    /// Medication reminders, as the server has it (already off with Health turned off); nil from
    /// servers that don't send it (their medicine routes answer 404 when off).
    public var medications: Bool? = nil
    /// How long a new event lasts when no end is given, in minutes; nil from older servers.
    public var defaultEventMinutes: Int? = nil
    /// defaultEventMinutes, or an hour when the server doesn't say.
    public var eventMinutes: Int { defaultEventMinutes.flatMap { $0 > 0 ? $0 : nil } ?? 60 }
    /// The switches to go by: all on when the server sent none.
    public var on: Features { features ?? Features() }
    /// Medicines show only with medication reminders on and the Health tracker on, as on the server.
    public var medicinesOn: Bool { medications != false && on.trackersHealth }
}

/// What a family turned on or off in Kinwall's settings (GET /api/settings `features`). A switch
/// the server doesn't send (an older server, or one added later) counts as on, and one the apps
/// don't know is ignored, so neither breaks decoding.
public struct Features: Codable, Hashable, Sendable {
    public var chores = true, lists = true, contacts = true, paint = true, photos = true, notes = true, meals = true,
               messages = true, newscast = true, trackersReading = true, trackersMemories = true, trackersHealth = true, checkIns = true, polls = true

    public init() {}
    private enum CodingKeys: String, CodingKey {
        case chores, lists, contacts, paint, photos, notes, meals, messages, newscast, trackersReading, trackersMemories, trackersHealth, checkIns, polls
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func on(_ key: CodingKeys) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: key)) ?? true }
        chores = on(.chores); lists = on(.lists); contacts = on(.contacts); paint = on(.paint); photos = on(.photos)
        notes = on(.notes); meals = on(.meals); messages = on(.messages); newscast = on(.newscast)
        trackersReading = on(.trackersReading); trackersMemories = on(.trackersMemories); trackersHealth = on(.trackersHealth); checkIns = on(.checkIns)
        polls = on(.polls)
    }
}

/// A chore as it stands on one day (GET /api/chores/day).
public struct ChoreDay: Codable, Identifiable, Hashable, Sendable {
    public struct Checklist: Codable, Hashable, Sendable {
        public let listId: String
        public let name: String
        public let total: Int
        public let done: Int
        public var isFinished: Bool { done >= total }
    }
    public let id: String
    public let title: String
    public let emoji: String?
    /// nil = an "Anyone" chore.
    public let memberId: String?
    public let points: Int
    public let completed: Bool
    public let completedBy: String?
    public let checklist: Checklist?
    /// Ticked from a display key (the widgets, the Watch, Siri) and waiting for a parent's OK: not
    /// `completed` and no points yet. Nil from servers older than approvals.
    public var pending: Bool? = nil
    public var isAnyone: Bool { memberId == nil }
    /// Done or waiting for an OK: either way it's ticked, and ticking it again does nothing new.
    public var isTicked: Bool { completed || pending == true }
}

public struct FamilyList: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case todo, shopping, reusable }
    public let id: String
    public let name: String
    public let emoji: String?
    public let kind: Kind
    public let archived: Bool
    public let itemCount: Int
    public let openCount: Int
    /// Shopping lists: "groceries" or "shopping" (the list's type). Nil on other kinds and from
    /// servers older than list types.
    public let catalog: String?
    /// The family's default list for its type (server migration 0088); nil from older servers.
    public let isDefault: Bool?

    /// The shopping list Siri, the controls and the List widget mean by default: the family's default
    /// Groceries list, else the first Groceries-type list, else one named Groceries, else the first
    /// shopping list. Archived lists skipped.
    public static func groceries(in lists: [FamilyList]) -> FamilyList? {
        let open = lists.filter { !$0.archived }
        let isGroceries = { (l: FamilyList) in l.kind == .shopping && l.catalog == "groceries" }
        return open.first { isGroceries($0) && $0.isDefault == true }
            ?? open.first(where: isGroceries)
            ?? open.first { $0.name.trimmingCharacters(in: .whitespaces).localizedCaseInsensitiveCompare("Groceries") == .orderedSame }
            ?? open.first { $0.kind == .shopping }
    }
}

public struct ListItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let listId: String
    public let title: String
    public let notes: String?
    public let quantity: String?
    public let category: String?
    public let memberId: String?
    public let dueDate: String?
    public let priority: String?
    public let done: Bool
    /// Only from an add with skipExisting: "open" (it was already there) or "reopened" (unticked).
    public var existing: String? = nil

    /// What Siri says after an add.
    public func addedLine(to list: String) -> String {
        switch existing {
        case "open": "\(title) is already on \(list)."
        case "reopened": "Added \(title) back to \(list)."
        default: "Added \(title) to \(list)."
        }
    }
}

/// GET /api/lists/{id}: the list and its items (in the list's own sort order).
public struct ListDetail: Codable, Hashable, Sendable {
    public struct Suggestions: Codable, Hashable, Sendable {
        /// The household's stores (shopping lists), for "Start shopping at …".
        public let stores: [String]
    }
    public let list: FamilyList
    public let items: [ListItem]
    public var suggestions: Suggestions? = nil
}

// ---- Medicines (GET /api/medications/due): the "Take now" cards ----

/// A dose due now. `name` and `dose` are nil where the server keeps them off (a shared wall
/// without medicationNamesOnWalls); a person's own device gets theirs.
public struct DueDose: Codable, Identifiable, Hashable, Sendable {
    public let medicationId: String
    public let memberId: String
    /// The household day and HH:MM it's for (what POST /api/medications/{id}/doses takes back).
    public let date: String
    public let time: String
    public let dueAt: String
    public let name: String?
    public let dose: String?
    public var id: String { "\(medicationId):\(date):\(time)" }
    public init(medicationId: String, memberId: String, date: String, time: String, dueAt: String, name: String?, dose: String?) {
        self.medicationId = medicationId; self.memberId = memberId; self.date = date; self.time = time; self.dueAt = dueAt; self.name = name; self.dose = dose
    }
}

public struct DueDoses: Codable, Hashable, Sendable {
    /// Whether the server sent names at all.
    public let names: Bool
    public let doses: [DueDose]
    public init(names: Bool, doses: [DueDose]) { self.names = names; self.doses = doses }
}

// ---- Pairing (TV-style: the app shows a code, an admin approves it in Kinwall) ----

public struct PairStart: Codable, Sendable {
    public let pairingId: String
    public let code: String
    public let pollToken: String
    public let expiresAt: String
}

public enum PairPoll: Decodable, Sendable, Equatable {
    case pending
    case approved(key: String)

    private enum Keys: String, CodingKey { case status, key }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .status) {
        case "approved": self = .approved(key: try c.decode(String.self, forKey: .key))
        default: self = .pending
        }
    }
}

// ---- The Board (GET /api/board): today and the days ahead, for widgets and the watch ----

public struct BoardEvent: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    /// ISO instants for timed events; YYYY-MM-DD for all-day ones.
    public let start: String
    public let end: String
    public let allDay: Bool
    public let memberIds: [String]
    public let color: String?
    public let location: String?
    /// When to leave for it (ISO), if it has travel time.
    public let leaveAt: String?
    /// The household-local day it's listed under.
    public let date: String

    public init(id: String, title: String, start: String, end: String, allDay: Bool, memberIds: [String], color: String?, location: String?, leaveAt: String?, date: String) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.allDay = allDay
        self.memberIds = memberIds; self.color = color; self.location = location; self.leaveAt = leaveAt; self.date = date
    }

    public var startDate: Date? { allDay ? nil : ISO8601.parse(start) }
    public var endDate: Date? { allDay ? nil : ISO8601.parse(end) }
    public var leaveDate: Date? { leaveAt.flatMap(ISO8601.parse) }
}

public struct BoardItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let listId: String
    public let title: String
    public let listName: String
    public let listEmoji: String?
    public let dueDate: String?
    public let overdue: Bool
    public let memberId: String?
}

public struct Board: Codable, Hashable, Sendable {
    public struct ChoreProgress: Codable, Hashable, Sendable {
        /// nil = the Anyone chores.
        public let memberId: String?
        public let name: String?
        public let avatar: String?
        public let color: String?
        public let remaining: Int
        public let total: Int
        public init(memberId: String?, name: String?, avatar: String?, color: String?, remaining: Int, total: Int) {
            self.memberId = memberId; self.name = name; self.avatar = avatar; self.color = color; self.remaining = remaining; self.total = total
        }
    }
    public let today: String
    public let events: [BoardEvent]
    public let items: [BoardItem]
    public let chores: [ChoreProgress]
    /// The planned meals in these days ("What's for dinner"); nil from servers that don't send them.
    public var meals: [Meal]? = nil

    public init(today: String, events: [BoardEvent], items: [BoardItem], chores: [ChoreProgress], meals: [Meal]? = nil) {
        self.today = today; self.events = events; self.items = items; self.chores = chores; self.meals = meals
    }

    /// Without what the family turned off: no chores with chores off, no due items with lists off,
    /// no meals with meals off (newer servers already leave them out; older ones don't).
    public func respecting(_ features: Features) -> Board {
        Board(today: today, events: events, items: features.lists ? items : [], chores: features.chores ? chores : [], meals: features.meals ? meals : meals.map { _ in [] })
    }

    /// Timed events today that haven't ended, soonest first; `now` is the first one under way.
    public func nowAndNext(at now: Date = .now) -> (now: BoardEvent?, next: BoardEvent?) {
        let today = events.filter { $0.date == self.today && !$0.allDay }
        let current = today.first { ($0.startDate ?? .distantFuture) <= now && now < ($0.endDate ?? .distantPast) }
        let next = today.filter { ($0.startDate ?? .distantPast) > now }.min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        return (current, next)
    }
}

/// An event occurrence from GET /api/events, with what's needed to remind about it on the device.
public struct EventInstance: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    /// ISO instant for timed events; YYYY-MM-DD for all-day ones.
    public let start: String
    public let allDay: Bool
    public let location: String?
    public let memberIds: [String]
    /// Minutes before start (or before leaveAt when remindBeforeLeave) to remind; nil or [] = none.
    public let reminders: [Int]?
    public let leaveAt: String?
    public let remindBeforeLeave: Bool

    public init(id: String, title: String, start: String, allDay: Bool, location: String?, memberIds: [String], reminders: [Int]?, leaveAt: String?, remindBeforeLeave: Bool) {
        self.id = id; self.title = title; self.start = start; self.allDay = allDay; self.location = location
        self.memberIds = memberIds; self.reminders = reminders; self.leaveAt = leaveAt; self.remindBeforeLeave = remindBeforeLeave
    }

    public var startDate: Date? { allDay ? nil : ISO8601.parse(start) }
    public var leaveDate: Date? { leaveAt.flatMap(ISO8601.parse) }
}

enum ISO8601 {
    static func parse(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
