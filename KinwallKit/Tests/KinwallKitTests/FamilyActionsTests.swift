import Foundation
import Testing
@testable import KinwallKit

// The pure parts of Siri's "What's for dinner", Log reading and Vote in a poll (FamilyActions.swift).

private func meal(_ title: String, slot: String = "dinner", date: String = "2026-10-07", kind: String = "recipe", restaurant: String? = nil, order: String? = nil, time: String? = nil) -> Meal {
    Meal(id: title, date: date, slot: slot, title: title, mealKind: kind, recipeId: nil, restaurantId: restaurant, orderType: order, plannedTime: time)
}

@Suite struct DinnerTests {
    func say(_ meals: [Meal], now: String = "16:00", restaurants: [String: String] = [:]) -> String {
        Dinner.spoken(meals: meals, today: "2026-10-07", now: now, restaurants: restaurants, clock: { $0 })
    }

    @Test func tonightsDinner() {
        #expect(say([meal("Tacos")]) == "Dinner tonight is Tacos.")
        #expect(say([meal("Tacos", time: "18:00")]) == "Dinner tonight is Tacos, at 18:00.")
        #expect(say([meal("Tacos", date: "2026-10-08"), meal("Soup")]) == "Dinner tonight is Soup.", "tomorrow's isn't tonight's")
    }

    @Test func orderNightSaysWhereAndHow() {
        let r = ["r1": "Pizza Palace"]
        #expect(say([meal("Friday pizza", kind: "dining_out", restaurant: "r1", order: "pickup")], restaurants: r) == "Dinner tonight is pickup from Pizza Palace.")
        #expect(say([meal("Pizza Palace", kind: "dining_out", restaurant: "r1", order: "delivery")], restaurants: r) == "Dinner tonight is delivery from Pizza Palace.")
        #expect(say([meal("Pizza Palace", kind: "dining_out", restaurant: "r1", order: "dine_in", time: "18:30")], restaurants: r) == "Dinner tonight is out at Pizza Palace, at 18:30.")
        #expect(say([meal("Noodle House", kind: "dining_out", restaurant: "gone")]) == "Dinner tonight is from Noodle House.", "a restaurant it can't read goes by the meal's name")
    }

    @Test func twoDinners() {
        #expect(say([meal("Tacos"), meal("Salad")]) == "Dinner tonight is Tacos and Salad.")
    }

    @Test func noDinnerSaysWhatsNextToday() {
        #expect(say([meal("Grilled cheese", slot: "lunch"), meal("Apple slices", slot: "snack")], now: "10:00") == "Nothing's planned for dinner tonight. Next today: Grilled cheese for lunch.")
        #expect(say([meal("Grilled cheese", slot: "lunch"), meal("Apple slices", slot: "snack")], now: "13:00") == "Nothing's planned for dinner tonight. Next today: Apple slices for a snack.")
        #expect(say([meal("Pancakes", slot: "breakfast"), meal("Popcorn", slot: "snack", time: "19:00")], now: "17:00") == "Nothing's planned for dinner tonight. Next today: Popcorn for a snack.", "its own time over the slot's")
    }

    @Test func nothingPlanned() {
        #expect(say([]) == "Nothing's planned for dinner tonight.")
        #expect(say([meal("Pancakes", slot: "breakfast")], now: "17:00") == "Nothing's planned for dinner tonight.")
    }

    @Test func boardCarriesMealsAndDropsThemWithMealsOff() throws {
        let json = #"{"today":"2026-10-07","events":[],"items":[],"chores":[],"meals":[{"id":"x","date":"2026-10-07","slot":"dinner","title":"Tacos","mealKind":"recipe","recipeId":null,"restaurantId":null,"orderType":null,"plannedTime":null,"status":"planned"}]}"#
        let board = try JSONDecoder().decode(Board.self, from: Data(json.utf8))
        #expect(board.meals?.map(\.title) == ["Tacos"])
        var off = Features(); off.meals = false
        #expect(board.respecting(off).meals == [])
        #expect(board.respecting(Features()).meals?.count == 1)
        let old = try JSONDecoder().decode(Board.self, from: Data(#"{"today":"2026-10-07","events":[],"items":[],"chores":[]}"#.utf8))
        #expect(old.meals == nil, "older servers send no meals")
    }
}

@Suite struct ReadingLogTests {
    func entry(_ data: String, title: String = "Holes") throws -> ReadingEntry {
        try JSONDecoder().decode(ReadingEntry.self, from: Data(#"{"id":"t1","memberId":"m3","title":"\#(title)","data":\#(data)}"#.utf8))
    }

    @Test func pagesMoveThePlaceOn() throws {
        let e = try entry(#"{"format":"book","status":"reading","pagesRead":100,"totalPages":240}"#)
        let log = e.logged(20)
        #expect(log.patch == ReadingPatch(pagesRead: 120, minutesListened: nil, status: nil))
        #expect(log.line(for: "Maya") == "Logged 20 pages of Holes for Maya. Now on page 120 of 240.")
        #expect(e.logged(1).line(for: nil) == "Logged 1 page of Holes. Now on page 101 of 240.")
    }

    @Test func theLastPageFinishesIt() throws {
        let e = try entry(#"{"status":"reading","pagesRead":230,"totalPages":240}"#) // no format: a book
        let log = e.logged(50)
        #expect(log.patch == ReadingPatch(pagesRead: 240, minutesListened: nil, status: "finished"))
        #expect(log.line(for: "Maya") == "Logged 10 pages of Holes for Maya. That's the last page, so it's marked finished!")
    }

    @Test func audiobooksCountMinutes() throws {
        let e = try entry(#"{"format":"audiobook","status":"reading","minutesListened":60}"#)
        let log = e.logged(30)
        #expect(log.patch == ReadingPatch(pagesRead: nil, minutesListened: 90, status: nil))
        #expect(log.line(for: nil) == "Logged 30 minutes of Holes.")
        #expect(e.isAudiobook)
    }

    @Test func patchSendsOnlyWhatChanged() throws {
        let body = try JSONEncoder().encode(ReadingPatch.Body(data: ReadingPatch(pagesRead: 12, minutesListened: nil, status: nil)))
        #expect(String(decoding: body, as: UTF8.self) == #"{"data":{"pagesRead":12}}"#)
    }
}

@Suite struct PollTests {
    @Test func decodesAndNamesTheChoice() throws {
        let json = #"[{"id":"p1","question":"Friday dinner?","status":"open","options":[{"id":"o1","label":"Tacos","votes":["m1"]},{"id":"o2","label":"Pizza","votes":[]}]},{"id":"p2","question":"Old","status":"closed","options":[]}]"#
        let polls = try JSONDecoder().decode([Poll].self, from: Data(json.utf8))
        #expect(polls.filter(\.isOpen).map(\.id) == ["p1"])
        #expect(polls[0].options.map(\.label) == ["Tacos", "Pizza"])
        #expect(Poll.votedLine(voter: "Maya", choice: "Pizza", question: "Friday dinner?") == "Maya voted for Pizza in Friday dinner?")
        #expect(Poll.votedLine(voter: "Maya", choice: "Pizza", question: "Where should we go") == "Maya voted for Pizza in Where should we go.")
    }

    @Test func featureSwitch() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"familyName":"F","weekStart":1,"features":{"polls":false}}"#.utf8))
        #expect(!s.on.polls)
        #expect(Features().polls)
    }
}
