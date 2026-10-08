import Foundation
import Testing
@testable import KinwallKit

@Suite struct ShareTests {
    let page = URL(string: "https://example.org/tacos")!

    @Test func aLinkGoesAloneSoKinwallReadsIt() {
        #expect(Share.request(kind: nil, url: page) == .init(kind: nil, url: page.absoluteString, text: nil, name: nil))
        // Shared text that's only a link is a link.
        #expect(Share.request(kind: nil, text: "  https://example.org/tacos\n")?.url == page.absoluteString)
        // A Maps place keeps its name; a kind picked in Shortcuts goes along.
        let maps = URL(string: "https://maps.apple.com/place?name=Joe%27s")!
        #expect(Share.request(kind: nil, url: maps, name: "Joe's") == .init(kind: nil, url: maps.absoluteString, text: nil, name: "Joe's"))
        #expect(Share.request(kind: .restaurant, url: page)?.kind == .restaurant)
    }

    @Test func textNeedsItsKind() {
        #expect(Share.request(kind: nil, text: "Spring fair Sat May 9") == nil)
        #expect(Share.request(kind: .event, text: " Spring fair\n") == .init(kind: .event, url: nil, text: "Spring fair", name: nil))
        #expect(Share.request(kind: .recipe, text: "Lemon chicken") == nil) // a recipe needs its page
        #expect(Share.request(kind: .book, text: "  ") == nil)
        // A link inside more text is text.
        #expect(Share.request(kind: .event, text: "Party! https://example.org/rsvp")?.text == "Party! https://example.org/rsvp")
    }

    @Test func links() {
        #expect(Share.onlyLink("https://example.org/a b") == nil)
        #expect(Share.onlyLink("mailto:x@example.org") == nil)
        #expect(Share.firstLink(in: "Try this: https://example.org/tacos!")?.host == "example.org")
        #expect(Share.isMapsPlace(URL(string: "https://maps.apple.com/?q=Pizza")!))
        #expect(!Share.isMapsPlace(page))
        #expect(Share.vCardName("BEGIN:VCARD\r\nVERSION:3.0\r\nN:;Joe's Pizza;;;\r\nFN:Joe's Pizza\\, Main St\r\nEND:VCARD") == "Joe's Pizza, Main St")
        #expect(Share.vCardName("BEGIN:VCARD\nEND:VCARD") == nil)
    }

    @Test func answers() {
        let ok = Data(#"{"kind":"event","summary":"Check the event: Spring fair, Sat May 9","link":"https://k/#/calendar?draft=event","review":true}"#.utf8)
        guard case .done(let r) = Share.outcome(status: 200, data: ok) else { Issue.record("not done"); return }
        #expect(r.summary == "Check the event: Spring fair, Sat May 9" && r.needsReview)
        let book = Data(#"{"kind":"book","summary":"Added Wool to the library","link":"https://k/#/trackers/library?book=b1","review":false}"#.utf8)
        guard case .done(let b) = Share.outcome(status: 200, data: book) else { Issue.record("not done"); return }
        #expect(!b.needsReview)
        #expect(Share.outcome(status: 403, data: Data(#"{"error":"Meals is off","summary":"Meals is off"}"#.utf8)) == .failed("Meals is off"))
        // A wall screen's or kid's key: the auth layer's 403 has no summary.
        #expect(Share.outcome(status: 403, data: Data(#"{"error":"display key cannot access this route"}"#.utf8)) == .failed(Share.signInMessage))
        #expect(Share.outcome(status: 401, data: Data()) == .failed(Share.signInMessage))
        #expect(Share.outcome(status: 500, data: Data()) == .failed("Couldn't add it to Kinwall: error 500."))
    }

    @Test func openingTheAppAtTheLink() {
        let link = "https://k.example/#/calendar?draft=event&title=Spring+fair&date=2026-05-09"
        let app = Share.appLink(link)!
        #expect(app.absoluteString == "family.kinwall.app:/open?to=shared&link=https://k.example/%23/calendar?draft%3Devent%26title%3DSpring%2Bfair%26date%3D2026-05-09")
        #expect(URLComponents(url: app, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "to", value: "shared"), URLQueryItem(name: "link", value: link)])
    }

    @Test func prompts() {
        #expect(Share.prompt(.recipe, text: "x") == nil)
        #expect(Share.prompt(.book, text: "WOOL\nHugh Howey")!.hasSuffix("Author: its author\n\nWOOL\nHugh Howey"))
        #expect(Share.prompt(.restaurant, text: "m")!.contains("Menu:\nthen each menu section's name"))
        #expect(Share.prompt(.event, text: "f")!.contains("Place: the venue's name and its full street address and town on one line, like The Rivers Residence, 12 Elm Road, Springfield\nNotes: anything else worth knowing, like what to bring, costs, or how to RSVP"))
    }

    @Test func theModelsGuess() {
        let g = Share.guess("Kind: event\nTitle: Spring Fair\nDate: Saturday, May 9, 2026\nPlace: Lincoln Elementary")
        #expect(g?.kind == .event && g?.text == "Title: Spring Fair\nDate: Saturday, May 9, 2026\nPlace: Lincoln Elementary")
        #expect(Share.guess("\n**Kind:** Book\nTitle: Wool")?.kind == .book)
        #expect(Share.guess("Kind: unsure") == nil)
        #expect(Share.guess("Kind: event") == nil) // nothing to send
        #expect(Share.guess("Title: Wool") == nil)
        #expect(Share.guessPrompt(text: "flyer").hasSuffix("how to RSVP\n\nflyer"))
    }

    @Test func theGuessInOneLine() {
        #expect(Share.guessLine(.event, text: "Title: Spring fair\nDate: Sat May 9\nTime: 10 AM") == "Looks like an event: Spring fair, Sat May 9")
        #expect(Share.guessLine(.book, text: "Title: Wool\nAuthor: Hugh Howey") == "Looks like a book: Wool")
        #expect(Share.guessLine(.restaurant, text: "Menu:\nPizza 12") == "Looks like a menu")
        #expect(Share.guessLine(.book, text: "Title: " + String(repeating: "a", count: 80)).count == "Looks like a book: ".count + 60)
        #expect(Share.notLabel(.event) == "Not an event?" && Share.notLabel(.restaurant) == "Not a menu?")
    }

    @Test func anEventToCheckComesWithWhatWasRead() throws {
        let ok = Data(#"{"kind":"event","summary":"Check the event: Spring fair","link":"https://k/#/calendar?draft=event","review":true,"event":{"title":"Spring fair","date":"2026-05-09","time":"10:00","end":null,"place":null}}"#.utf8)
        guard case .done(let r) = Share.outcome(status: 200, data: ok) else { Issue.record("not done"); return }
        #expect(r.needsReview && r.event == .init(title: "Spring fair", date: "2026-05-09", time: "10:00"))
        // Saved: not to check, even though it's an event.
        let saved = Data(#"{"kind":"event","summary":"Added Spring fair to Family, Sat May 9","link":"https://k/#/calendar?event=e1","review":false}"#.utf8)
        guard case .done(let s) = Share.outcome(status: 200, data: saved) else { Issue.record("not done"); return }
        #expect(!s.needsReview && s.event == nil)
        // Saving sends the checked event, the calendar and save; nothing else.
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Share.Request(kind: .event, event: .init(title: "Swim", date: "2026-05-09"), save: true, calendarId: "c1"))) as! [String: Any]
        #expect(Set(body.keys) == ["kind", "event", "save", "calendarId"])
        #expect(body["event"] as? [String: String] == ["title": "Swim", "date": "2026-05-09"])
    }

    @Test func theModelsLinesThenTheWordsAsRead() {
        #expect(Share.eventText("Title: Swim\nPlace: Oak Pool", raw: "SWIM\n9 Lake Ave") == "Title: Swim\nPlace: Oak Pool\n---\nSWIM\n9 Lake Ave")
        #expect(Share.eventText(nil, raw: "SWIM") == "SWIM")
        #expect(Share.eventText(" SWIM\n", raw: "SWIM") == "SWIM", "no model: the words once")
    }

    @Test func calendarsToAddTo() {
        let cals = [Share.FamilyCalendar(id: "a", name: "Family"), .init(id: "b", name: "School", writable: false), .init(id: "c", name: "Old", enabled: false),
                    .init(id: "d", name: "Work", canEditEvents: false), .init(id: "e", name: "Kids", canEditEvents: nil)]
        #expect(Share.addable(cals).map(\.id) == ["a", "e"])
        let json = Data(#"[{"id":"a","name":"Family","writable":true,"enabled":true,"canEditEvents":true,"kind":"local"}]"#.utf8)
        #expect(try! JSONDecoder().decode([Share.FamilyCalendar].self, from: json) == [.init(id: "a", name: "Family")])
        // The family's default calendar for new events comes first; the rest keep Kinwall's order.
        let marked = Data(#"[{"id":"a","name":"A meal kit","writable":true,"enabled":true,"default":false},{"id":"b","name":"Our Family","writable":true,"enabled":true,"default":true},{"id":"c","name":"Work","writable":true,"enabled":true}]"#.utf8)
        #expect(Share.addable(try! JSONDecoder().decode([Share.FamilyCalendar].self, from: marked)).map(\.id) == ["b", "a", "c"])
    }

    @Test func thePickersKeepTheHouseholdsClock() {
        let start = Share.pickerDate("2026-10-17", "15:00")!, end = Share.pickerDate("2026-10-17", "17:00")!
        #expect(Share.draft(title: " Maya's party ", place: "The Rivers Residence, 12 Elm Road", notes: " Bring a towel\n", day: start, start: start, end: end, allDay: false)
                == .init(title: "Maya's party", date: "2026-10-17", time: "15:00", end: "17:00", place: "The Rivers Residence, 12 Elm Road", notes: "Bring a towel"))
        #expect(Share.draft(title: "Fair", place: " ", day: Share.pickerDate("2026-05-09")!, start: start, end: end, allDay: true)
                == .init(title: "Fair", date: "2026-05-09"))
        #expect(Share.pickerDate(nil, "10:00") == nil)
    }

    // Several photos of one menu (the share sheet, Add to Kinwall).

    @Test func photosAreJoinedWithPageLines() {
        #expect(Share.joinPages(["Pizza\nCheese 12", "  ", "Sides\nFries 3\n"]) == "Pizza\nCheese 12\n--- Page 2 ---\nSides\nFries 3")
        #expect(Share.joinPages(["Only one\n"]) == "Only one")
        #expect(Share.joinPages([]) == "")
    }

    @Test func aLongMenuIsChunkedByPageThenByLine() {
        let short = ["Name: Corner Slice\nPizza\nCheese 12", "Sides\nFries 3"]
        #expect(Share.chunks(short, limit: 100) == [Share.joinPages(short)], "short enough: one go")
        let page = (1...30).map { "Item \($0) 9.99" }.joined(separator: "\n") // ~400 characters
        let three = [page, page, page]
        let parts = Share.chunks(three, limit: 900)
        #expect(parts.count == 2, "two pages fit, then the third")
        #expect(parts.allSatisfy { $0.count <= 900 })
        #expect(parts[1].hasPrefix("--- Page 3 ---"))
        // A page over the limit on its own is split between lines; nothing is lost.
        let long = Share.chunks([page], limit: 150)
        #expect(long.allSatisfy { $0.count <= 150 })
        #expect(long.joined(separator: "\n") == page)
    }

    @Test func laterChunksAskForMenuLinesOnly() {
        let more = Share.morePrompt(text: "Sides\nFries 3")
        #expect(more.contains("Fries 3"))
        #expect(!more.contains("Name:"))
        #expect(Share.prompt(.restaurant, text: "Pizza")!.contains("Name:"))
    }

    @Test func guessLineCountsPagesAndSaysWhenTheRestaurantIsThere() {
        #expect(Share.guessLine(.restaurant, text: "Name: Corner Slice\nMenu:\nPizza 12", pages: 3) == "Looks like a menu: Corner Slice, 3 pages")
        #expect(Share.guessLine(.restaurant, text: "", pages: 2) == "Looks like a menu: 2 pages")
        #expect(Share.guessLine(.event, text: "Title: Spring fair", pages: 2) == "Looks like an event: Spring fair")
        #expect(Share.alreadyThere("Corner Slice", pages: 3) == "Corner Slice is already in Kinwall, so these will be added to its menu.")
        #expect(Share.alreadyThere("Corner Slice", pages: 1) == "Corner Slice is already in Kinwall, so this will be added to its menu.")
        #expect(Share.name(in: "Name: Corner Slice\nMenu:") == "Corner Slice")
        #expect(Share.sameName("corner slice!", "Corner Slice"))
        #expect(!Share.sameName("Corner Slice", "Corner Cafe"))
    }
}
