import Foundation

/// The demo family ("Our Family"), built in: while the app shows the demo (src/demo.ts sets
/// SharedKeychain.demoStore), the widgets, Siri and the Controls use this instead of calling a
/// server, so a visitor or an App Store reviewer sees them work with no sign-in. Never while a
/// real family is connected. Nothing here is ever sent anywhere.
public enum DemoFamily {
    #if canImport(Security)
    /// The demo is showing and no real family is connected.
    public static var isOn: Bool { isOn(family: SharedKeychain.widgetStore, demo: SharedKeychain.demoStore) }
    #endif
    /// Only when the family's key is surely absent: a Keychain read that fails is not "no family",
    /// or Siri would answer from the demo and save nothing while a real family is signed in.
    public static func isOn(family: ConnectionStore, demo: ConnectionStore) -> Bool {
        guard let noFamily = try? family.load() == nil, noFamily else { return false }
        return (try? demo.load()) != nil
    }

    public static let members: [Member] = decode("""
    [{"id":"m1","name":"Alex","color":"#7AB8FF","avatar":"🦊","pointsToday":10,"pointsWeek":40,"balance":12},
     {"id":"m2","name":"Sam","color":"#FF8FA3","avatar":"🐰","pointsToday":5,"pointsWeek":25,"balance":30},
     {"id":"m3","name":"Maya","color":"#7ED9A6","avatar":"🦄","pointsToday":5,"pointsWeek":15,"balance":42},
     {"id":"m4","name":"Leo","color":"#F5A65B","avatar":"🦖","pointsToday":0,"pointsWeek":20,"balance":18}]
    """)
    public static let chores: [ChoreDay] = decode("""
    [{"id":"ch2","title":"Feed the dog","emoji":"🐕","memberId":"m3","points":5,"completed":true,"completedBy":"m3"},
     {"id":"ch7","title":"Practice piano","emoji":"🎹","memberId":"m3","points":10,"completed":false},
     {"id":"ch6","title":"Tidy toys","emoji":"🧸","memberId":"m4","points":5,"completed":false},
     {"id":"ch8","title":"Take out the recycling","emoji":"♻️","memberId":"m4","points":5,"completed":false},
     {"id":"ch4","title":"Water plants","emoji":"🪴","points":5,"completed":false}]
    """)
    public static let groceries: ListDetail = decode("""
    {"list":{"id":"l1","name":"Groceries","emoji":"🛒","kind":"shopping","catalog":"groceries","archived":false,"itemCount":6,"openCount":5},
     "items":[{"id":"li1","listId":"l1","title":"Milk","quantity":"1 gal","done":false},
              {"id":"li2","listId":"l1","title":"Eggs","quantity":"1 dozen","done":false},
              {"id":"li4","listId":"l1","title":"Apples","quantity":"6","done":false},
              {"id":"li5","listId":"l1","title":"Paper towels","done":false},
              {"id":"g1","listId":"l1","title":"Blueberries","quantity":"3 pints","done":false},
              {"id":"li3","listId":"l1","title":"Bread","done":true}],
     "suggestions":{"stores":["Neighborhood market","Warehouse club"]}}
    """)
    public static let lists: [FamilyList] = [groceries.list] + decode("""
    [{"id":"l2","name":"Weekend To-Dos","emoji":"✅","kind":"todo","archived":false,"itemCount":5,"openCount":4}]
    """)

    /// Today around `now`: reading time under way, soccer (leave in 5 minutes), piano, movie night; tacos for dinner.
    public static func board(now: Date = .now) -> Board {
        let iso = ISO8601DateFormatter()
        let day = HouseholdDate.key(for: now, timezone: nil)
        func event(_ id: String, _ title: String, _ from: Double, _ to: Double, leave: Double? = nil, color: String, members: [String] = []) -> BoardEvent {
            BoardEvent(id: id, title: title, start: iso.string(from: now.addingTimeInterval(from * 60)), end: iso.string(from: now.addingTimeInterval(to * 60)),
                       allDay: false, memberIds: members, color: color, location: nil, leaveAt: leave.map { iso.string(from: now.addingTimeInterval($0 * 60)) }, date: day)
        }
        return Board(today: day,
                     events: [event("a", "Reading time", -20, 25, color: "#7ED9A6"), event("b", "Soccer Practice", 20, 110, leave: 5, color: "#FF8FA3", members: ["m2"]), event("c", "Piano Lesson", 70, 115, color: "#7ED9A6", members: ["m3"]), event("d", "Movie Night", 180, 300, color: "#B39DFF")],
                     items: [],
                     chores: [.init(memberId: "m3", name: "Maya", avatar: "🦄", color: "#7ED9A6", remaining: 1, total: 2), .init(memberId: "m4", name: "Leo", avatar: "🦖", color: "#F5A65B", remaining: 2, total: 2),
                              .init(memberId: nil, name: nil, avatar: nil, color: nil, remaining: 1, total: 1)],
                     meals: [Meal(id: "meal1", date: day, slot: "dinner", title: "Tacos", mealKind: "recipe", recipeId: nil, restaurantId: nil, orderType: nil, plannedTime: "18:00")])
    }

    /// Two doses due a few minutes ago, Sam's and Leo's, without names (a shared device's view).
    public static func dueDoses(now: Date = .now) -> DueDoses {
        let iso = ISO8601DateFormatter()
        let due = now.addingTimeInterval(-10 * 60)
        let day = HouseholdDate.key(for: due, timezone: nil)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let hm = String(format: "%02d:%02d", cal.component(.hour, from: due), cal.component(.minute, from: due))
        return DueDoses(names: false, doses: [
            DueDose(medicationId: "med1", memberId: "m2", date: day, time: hm, dueAt: iso.string(from: due), name: nil, dose: nil),
            DueDose(medicationId: "med2", memberId: "m4", date: day, time: hm, dueAt: iso.string(from: due), name: nil, dose: nil),
        ])
    }

    /// The demo's check-in and battery are Maya's (m3), as if on her own phone.
    public static let checkInPerson = "m3"

    /// Maya's check-in this morning: nothing answered yet (the demo's widgets open the app to answer).
    public static func tempCheck(now: Date = .now) -> TempCheck {
        let day = HouseholdDate.key(for: now, timezone: nil)
        return decode("""
        {"memberId":"m3","date":"\(day)","settings":{"on":true,"sleep":true,"feelings":true,"goal":true,"evening":true,"eveningTime":"21:00","battery":true},
         "private":false,"goal":null,"followupOpen":false,"drainedOpen":false,"custom":[],
         "answered":{"sleep":false,"feelings":false,"goal":false,"followup":false,"drained":false}}
        """)
    }

    /// Maya's energy battery today and tomorrow (the web demo's, web/src/mock-insights.ts).
    public static func battery(now: Date = .now) -> Battery {
        let today = HouseholdDate.key(for: now, timezone: nil)
        let tomorrow = HouseholdDate.key(for: now.addingTimeInterval(86_400), timezone: nil)
        return decode("""
        {"on":true,"today":"\(today)","days":[
          {"date":"\(today)","forecast":false,"level":62,"reasons":[{"text":"Sleep: good","points":75},{"text":"1 event","points":-10},{"text":"Chores: 15 points","points":-8}]},
          {"date":"\(tomorrow)","forecast":true,"level":20,"reasons":[{"text":"5 events","points":-50}]}],
         "warnings":[{"date":"\(tomorrow)","text":"Tomorrow looks full: 5 events, 2 chores and a late evening."}]}
        """)
    }

    private static func decode<T: Decodable>(_ json: String) -> T { try! JSONDecoder().decode(T.self, from: Data(json.utf8)) }
}
